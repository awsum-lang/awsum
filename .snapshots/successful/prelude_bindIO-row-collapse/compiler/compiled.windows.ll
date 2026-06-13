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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"nevOk" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"kS" }
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

define internal ptr @v_seedNeverIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 5 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedAIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 5 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedLeftAIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 6 to ptr
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

define internal ptr @v_seedSIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 5 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedLeftSIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 6 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  ret ptr %t0
}

define internal ptr @v_seedTIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 5 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 4, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedFirstIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 6 to ptr
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

define internal ptr @v_seedSecondIO() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 6 to ptr
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
  %t0 = call ptr @v_seedNeverIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 38 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_0(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_nevFail() {
  %t0 = call ptr @v_seedNeverIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 40 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_4(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_nevRightOk() {
  %t0 = call ptr @v_seedAIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 42 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_8(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_nevRightE1() {
  %t0 = call ptr @v_seedLeftAIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 42 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_8(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_pureNever() {
  %t0 = call ptr @v_seedNeverIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 42 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_8(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_strOk() {
  %t0 = call ptr @v_seedSIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 44 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_0_bindIO_12(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_strE1() {
  %t0 = call ptr @v_seedLeftSIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 44 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_0_bindIO_12(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_strE2() {
  %t0 = call ptr @v_seedSIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 46 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_0_bindIO_16(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_strIdem() {
  %t0 = call ptr @v_seedSIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 48 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_20(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_abE1() {
  %t0 = call ptr @v_seedLeftAIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 50 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_4_bindIO_24(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_abE2() {
  %t0 = call ptr @v_seedAIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 50 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_4_bindIO_24(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_twoFirst() {
  %t0 = call ptr @v_seedFirstIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 52 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_8_bindIO_28(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_twoSecond() {
  %t0 = call ptr @v_seedSecondIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 52 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_8_bindIO_28(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_twoE2() {
  %t0 = call ptr @v_seedTIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 54 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_8_bindIO_32(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_twoOk() {
  %t0 = call ptr @v_seedTIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 52 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_8_bindIO_28(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_idemE1() {
  %t0 = call ptr @v_seedLeftAIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 40 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_4(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_idemE2() {
  %t0 = call ptr @v_seedAIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 40 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_4(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_idem2First() {
  %t0 = call ptr @v_seedFirstIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 56 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_36(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_idem2Second() {
  %t0 = call ptr @v_seedTIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 56 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df_bindIO_36(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_wE1() {
  %t0 = call ptr @v_seedFirstIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 60 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_16_bindIO_44(ptr %t0, ptr %t1)
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 58 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @v__cps__df__rowmono_12_bindIO_40(ptr %t4, ptr %t5)
  ret ptr %t8
}

define internal ptr @v_wE2str() {
  %t0 = call ptr @v_seedTIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 62 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_16_bindIO_48(ptr %t0, ptr %t1)
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 58 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @v__cps__df__rowmono_12_bindIO_40(ptr %t4, ptr %t5)
  ret ptr %t8
}

define internal ptr @v_wE3() {
  %t0 = call ptr @v_seedTIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 60 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_16_bindIO_44(ptr %t0, ptr %t1)
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 64 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @v__cps__df__rowmono_12_bindIO_52(ptr %t4, ptr %t5)
  ret ptr %t8
}

define internal ptr @v_wOk() {
  %t0 = call ptr @v_seedTIO()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 60 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__cps__df__rowmono_16_bindIO_44(ptr %t0, ptr %t1)
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 58 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @v__cps__df__rowmono_12_bindIO_40(ptr %t4, ptr %t5)
  ret ptr %t8
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t3
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
  %t13 = inttoptr i64 96 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__cps__df_andThenIO_116(ptr %t0, ptr %t12)
  %t16 = call ptr @v_nevOk()
  %t17 = call ptr @__alloc(i64 8, i32 0)
  %t18 = inttoptr i64 70 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @v__cps__df_mapIO_64(ptr %t16, ptr %t17)
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 68 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = call ptr @v__cps__df_andThenIO_60(ptr %t20, ptr %t21)
  %t25 = call ptr @__alloc(i64 8, i32 0)
  %t26 = inttoptr i64 66 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = call ptr @v__cps__df_handleErrorIO_56(ptr %t24, ptr %t25)
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 94 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_andThenIO_112(ptr %t15, ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 92 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_108(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 140 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_andThenIO_204(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 138 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_200(ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 136 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_196(ptr %t44, ptr %t45)
  %t49 = call ptr @__alloc(i64 8, i32 0)
  %t50 = inttoptr i64 134 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = call ptr @v__cps__df_andThenIO_192(ptr %t48, ptr %t49)
  %t53 = call ptr @__alloc(i64 8, i32 0)
  %t54 = inttoptr i64 132 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @v__cps__df_andThenIO_188(ptr %t52, ptr %t53)
  %t57 = call ptr @__alloc(i64 8, i32 0)
  %t58 = inttoptr i64 130 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = call ptr @v__cps__df_andThenIO_184(ptr %t56, ptr %t57)
  %t61 = call ptr @__alloc(i64 8, i32 0)
  %t62 = inttoptr i64 128 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = call ptr @v__cps__df_andThenIO_180(ptr %t60, ptr %t61)
  %t65 = call ptr @__alloc(i64 8, i32 0)
  %t66 = inttoptr i64 126 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @v__cps__df_andThenIO_176(ptr %t64, ptr %t65)
  %t69 = call ptr @__alloc(i64 8, i32 0)
  %t70 = inttoptr i64 124 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = call ptr @v__cps__df_andThenIO_172(ptr %t68, ptr %t69)
  %t73 = call ptr @__alloc(i64 8, i32 0)
  %t74 = inttoptr i64 122 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = call ptr @v__cps__df_andThenIO_168(ptr %t72, ptr %t73)
  %t77 = call ptr @__alloc(i64 8, i32 0)
  %t78 = inttoptr i64 120 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = call ptr @v__cps__df_andThenIO_164(ptr %t76, ptr %t77)
  %t81 = call ptr @__alloc(i64 8, i32 0)
  %t82 = inttoptr i64 118 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = call ptr @v__cps__df_andThenIO_160(ptr %t80, ptr %t81)
  %t85 = call ptr @__alloc(i64 8, i32 0)
  %t86 = inttoptr i64 116 to ptr
  %t87 = getelementptr ptr, ptr %t85, i32 0
  store ptr %t86, ptr %t87
  %t88 = call ptr @v__cps__df_andThenIO_156(ptr %t84, ptr %t85)
  %t89 = call ptr @__alloc(i64 8, i32 0)
  %t90 = inttoptr i64 114 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  %t92 = call ptr @v__cps__df_andThenIO_152(ptr %t88, ptr %t89)
  %t93 = call ptr @__alloc(i64 8, i32 0)
  %t94 = inttoptr i64 112 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  %t96 = call ptr @v__cps__df_andThenIO_148(ptr %t92, ptr %t93)
  %t97 = call ptr @__alloc(i64 8, i32 0)
  %t98 = inttoptr i64 110 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = call ptr @v__cps__df_andThenIO_144(ptr %t96, ptr %t97)
  %t101 = call ptr @__alloc(i64 8, i32 0)
  %t102 = inttoptr i64 108 to ptr
  %t103 = getelementptr ptr, ptr %t101, i32 0
  store ptr %t102, ptr %t103
  %t104 = call ptr @v__cps__df_andThenIO_140(ptr %t100, ptr %t101)
  %t105 = call ptr @__alloc(i64 8, i32 0)
  %t106 = inttoptr i64 106 to ptr
  %t107 = getelementptr ptr, ptr %t105, i32 0
  store ptr %t106, ptr %t107
  %t108 = call ptr @v__cps__df_andThenIO_136(ptr %t104, ptr %t105)
  %t109 = call ptr @__alloc(i64 8, i32 0)
  %t110 = inttoptr i64 104 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  %t112 = call ptr @v__cps__df_andThenIO_132(ptr %t108, ptr %t109)
  %t113 = call ptr @__alloc(i64 8, i32 0)
  %t114 = inttoptr i64 102 to ptr
  %t115 = getelementptr ptr, ptr %t113, i32 0
  store ptr %t114, ptr %t115
  %t116 = call ptr @v__cps__df_andThenIO_128(ptr %t112, ptr %t113)
  %t117 = call ptr @__alloc(i64 8, i32 0)
  %t118 = inttoptr i64 100 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  %t120 = call ptr @v__cps__df_andThenIO_124(ptr %t116, ptr %t117)
  %t121 = call ptr @__alloc(i64 8, i32 0)
  %t122 = inttoptr i64 98 to ptr
  %t123 = getelementptr ptr, ptr %t121, i32 0
  store ptr %t122, ptr %t123
  %t124 = call ptr @v__cps__df_andThenIO_120(ptr %t120, ptr %t121)
  ret ptr %t124
}

define internal ptr @v__cps__lift_38(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.25 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__lift_38(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t6)
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 6 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 2252990199 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t15)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t15, ptr %t22
  %t23 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t23
  %t24 = call ptr @v__apply__lift_38(ptr %t6, ptr %t16)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t36 = getelementptr i8, ptr %t5, i64 -8
  %t37 = load i32, ptr %t36
  %t38 = icmp eq i32 %t37, 1
  br i1 %t38, label %reuse.in_place.39, label %reuse.copy.40
reuse.in_place.39:
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__free_recursive(ptr %t31)
  %t34 = inttoptr i64 29 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t6)
  %t32 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t33
  br label %reuse.in_place.end.42
reuse.in_place.end.42:
  br label %reuse.join.41
reuse.copy.40:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 29 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t27)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t27, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.43
reuse.copy.end.43:
  br label %reuse.join.41
reuse.join.41:
  %t49 = phi ptr [ %t5, %reuse.in_place.end.42 ], [ %t44, %reuse.copy.end.43 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t50 = load ptr, ptr %t2
  ret ptr %t50
}

define internal ptr @v__apply__lift_38(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__lift_42(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.25 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__lift_42(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t6)
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 6 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 2269767818 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t15)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t15, ptr %t22
  %t23 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t23
  %t24 = call ptr @v__apply__lift_42(ptr %t6, ptr %t16)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t36 = getelementptr i8, ptr %t5, i64 -8
  %t37 = load i32, ptr %t36
  %t38 = icmp eq i32 %t37, 1
  br i1 %t38, label %reuse.in_place.39, label %reuse.copy.40
reuse.in_place.39:
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__free_recursive(ptr %t31)
  %t34 = inttoptr i64 31 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t6)
  %t32 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t33
  br label %reuse.in_place.end.42
reuse.in_place.end.42:
  br label %reuse.join.41
reuse.copy.40:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 31 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t27)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t27, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.43
reuse.copy.end.43:
  br label %reuse.join.41
reuse.join.41:
  %t49 = phi ptr [ %t5, %reuse.in_place.end.42 ], [ %t44, %reuse.copy.end.43 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t50 = load ptr, ptr %t2
  ret ptr %t50
}

define internal ptr @v__apply__lift_42(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__lift_46(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.25 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__lift_46(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t6)
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 6 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 2252990199 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t15)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t15, ptr %t22
  %t23 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t23
  %t24 = call ptr @v__apply__lift_46(ptr %t6, ptr %t16)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t36 = getelementptr i8, ptr %t5, i64 -8
  %t37 = load i32, ptr %t36
  %t38 = icmp eq i32 %t37, 1
  br i1 %t38, label %reuse.in_place.39, label %reuse.copy.40
reuse.in_place.39:
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__free_recursive(ptr %t31)
  %t34 = inttoptr i64 33 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t6)
  %t32 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t33
  br label %reuse.in_place.end.42
reuse.in_place.end.42:
  br label %reuse.join.41
reuse.copy.40:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 33 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t27)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t27, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.43
reuse.copy.end.43:
  br label %reuse.join.41
reuse.join.41:
  %t49 = phi ptr [ %t5, %reuse.in_place.end.42 ], [ %t44, %reuse.copy.end.43 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t50 = load ptr, ptr %t2
  ret ptr %t50
}

define internal ptr @v__apply__lift_46(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__lift_50(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.25 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__lift_50(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t6)
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 6 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 2252990199 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t15)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t15, ptr %t22
  %t23 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t23
  %t24 = call ptr @v__apply__lift_50(ptr %t6, ptr %t16)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t36 = getelementptr i8, ptr %t5, i64 -8
  %t37 = load i32, ptr %t36
  %t38 = icmp eq i32 %t37, 1
  br i1 %t38, label %reuse.in_place.39, label %reuse.copy.40
reuse.in_place.39:
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__free_recursive(ptr %t31)
  %t34 = inttoptr i64 35 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t6)
  %t32 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t33
  br label %reuse.in_place.end.42
reuse.in_place.end.42:
  br label %reuse.join.41
reuse.copy.40:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 35 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t27)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t27, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.43
reuse.copy.end.43:
  br label %reuse.join.41
reuse.join.41:
  %t49 = phi ptr [ %t5, %reuse.in_place.end.42 ], [ %t44, %reuse.copy.end.43 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t50 = load ptr, ptr %t2
  ret ptr %t50
}

define internal ptr @v__apply__lift_50(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__lift_54(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.25 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__lift_54(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t6)
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 6 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 1615808600 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t15)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t15, ptr %t22
  %t23 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t23
  %t24 = call ptr @v__apply__lift_54(ptr %t6, ptr %t16)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t36 = getelementptr i8, ptr %t5, i64 -8
  %t37 = load i32, ptr %t36
  %t38 = icmp eq i32 %t37, 1
  br i1 %t38, label %reuse.in_place.39, label %reuse.copy.40
reuse.in_place.39:
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__free_recursive(ptr %t31)
  %t34 = inttoptr i64 37 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t6)
  %t32 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t33
  br label %reuse.in_place.end.42
reuse.in_place.end.42:
  br label %reuse.join.41
reuse.copy.40:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 37 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t27)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t27, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.43
reuse.copy.end.43:
  br label %reuse.join.41
reuse.join.41:
  %t49 = phi ptr [ %t5, %reuse.in_place.end.42 ], [ %t44, %reuse.copy.end.43 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t50 = load ptr, ptr %t2
  ret ptr %t50
}

define internal ptr @v__apply__lift_54(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_bindIO_0(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.21 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 5 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @v__apply__df_bindIO_0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t20 = call ptr @v__apply__df_bindIO_0(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t20, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.21:
  %t22 = getelementptr ptr, ptr %t5, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr ptr, ptr %t5, i32 2
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t32 = getelementptr i8, ptr %t5, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t26 = getelementptr ptr, ptr %t5, i32 2
  %t27 = load ptr, ptr %t26
  call void @__free_recursive(ptr %t27)
  %t30 = inttoptr i64 39 to ptr
  %t31 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t6)
  %t28 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t28
  %t29 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t23, ptr %t29
  br label %reuse.in_place.end.38
reuse.in_place.end.38:
  br label %reuse.join.37
reuse.copy.36:
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 39 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  call void @__inc_ref(ptr %t6)
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t6, ptr %t43
  call void @__inc_ref(ptr %t23)
  %t44 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t23, ptr %t44
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.39
reuse.copy.end.39:
  br label %reuse.join.37
reuse.join.37:
  %t45 = phi ptr [ %t5, %reuse.in_place.end.38 ], [ %t40, %reuse.copy.end.39 ]
  call void @__inc_ref(ptr %t25)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t25)
  store ptr %t25, ptr %t3
  store ptr %t45, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t46 = load ptr, ptr %t2
  ret ptr %t46
}

define internal ptr @v__apply__df_bindIO_0(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_bindIO_4(ptr %v_io, ptr %v__k) {
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
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 24 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t18
  %t19 = call ptr @v__apply__df_bindIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.20:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t21 = call ptr @v__apply__df_bindIO_4(ptr %t6, ptr %t5)
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
  %t31 = inttoptr i64 41 to ptr
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
  %t42 = inttoptr i64 41 to ptr
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

define internal ptr @v__apply__df_bindIO_4(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_bindIO_8(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.21 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 5 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @v__apply__df_bindIO_8(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t20 = call ptr @v__apply__df_bindIO_8(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t20, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.21:
  %t22 = getelementptr ptr, ptr %t5, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr ptr, ptr %t5, i32 2
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t32 = getelementptr i8, ptr %t5, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t26 = getelementptr ptr, ptr %t5, i32 2
  %t27 = load ptr, ptr %t26
  call void @__free_recursive(ptr %t27)
  %t30 = inttoptr i64 43 to ptr
  %t31 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t6)
  %t28 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t28
  %t29 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t23, ptr %t29
  br label %reuse.in_place.end.38
reuse.in_place.end.38:
  br label %reuse.join.37
reuse.copy.36:
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 43 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  call void @__inc_ref(ptr %t6)
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t6, ptr %t43
  call void @__inc_ref(ptr %t23)
  %t44 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t23, ptr %t44
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.39
reuse.copy.end.39:
  br label %reuse.join.37
reuse.join.37:
  %t45 = phi ptr [ %t5, %reuse.in_place.end.38 ], [ %t40, %reuse.copy.end.39 ]
  call void @__inc_ref(ptr %t25)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t25)
  store ptr %t25, ptr %t3
  store ptr %t45, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t46 = load ptr, ptr %t2
  ret ptr %t46
}

define internal ptr @v__apply__df_bindIO_8(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_0_bindIO_12(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.23 i64 7, label %tco.case.arm.7.35 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 5 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 28 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @v__cps__lift_38(ptr %t12, ptr %t18)
  %t22 = call ptr @v__apply__df__rowmono_0_bindIO_12(ptr %t6, ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t22, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.23:
  %t24 = getelementptr ptr, ptr %t5, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t6)
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 6 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 1615808600 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t25)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t25, ptr %t32
  %t33 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t33
  %t34 = call ptr @v__apply__df__rowmono_0_bindIO_12(ptr %t6, ptr %t26)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t34, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.35:
  %t36 = getelementptr ptr, ptr %t5, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = getelementptr ptr, ptr %t5, i32 2
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t46 = getelementptr i8, ptr %t5, i64 -8
  %t47 = load i32, ptr %t46
  %t48 = icmp eq i32 %t47, 1
  br i1 %t48, label %reuse.in_place.49, label %reuse.copy.50
reuse.in_place.49:
  %t40 = getelementptr ptr, ptr %t5, i32 2
  %t41 = load ptr, ptr %t40
  call void @__free_recursive(ptr %t41)
  %t44 = inttoptr i64 45 to ptr
  %t45 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %t6)
  %t42 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t42
  %t43 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t37, ptr %t43
  br label %reuse.in_place.end.52
reuse.in_place.end.52:
  br label %reuse.join.51
reuse.copy.50:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 45 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t6)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t6, ptr %t57
  call void @__inc_ref(ptr %t37)
  %t58 = getelementptr ptr, ptr %t54, i32 2
  store ptr %t37, ptr %t58
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.53
reuse.copy.end.53:
  br label %reuse.join.51
reuse.join.51:
  %t59 = phi ptr [ %t5, %reuse.in_place.end.52 ], [ %t54, %reuse.copy.end.53 ]
  call void @__inc_ref(ptr %t39)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t39)
  store ptr %t39, ptr %t3
  store ptr %t59, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t60 = load ptr, ptr %t2
  ret ptr %t60
}

define internal ptr @v__apply__df__rowmono_0_bindIO_12(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_0_bindIO_16(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.24 i64 7, label %tco.case.arm.7.36 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 24 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 28 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v__cps__lift_38(ptr %t12, ptr %t19)
  %t23 = call ptr @v__apply__df__rowmono_0_bindIO_16(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__inc_ref(ptr %t6)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 6 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 1615808600 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t26)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t26, ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  %t35 = call ptr @v__apply__df__rowmono_0_bindIO_16(ptr %t6, ptr %t27)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t35, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.36:
  %t37 = getelementptr ptr, ptr %t5, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t47 = getelementptr i8, ptr %t5, i64 -8
  %t48 = load i32, ptr %t47
  %t49 = icmp eq i32 %t48, 1
  br i1 %t49, label %reuse.in_place.50, label %reuse.copy.51
reuse.in_place.50:
  %t41 = getelementptr ptr, ptr %t5, i32 2
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t45 = inttoptr i64 47 to ptr
  %t46 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t43 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t43
  %t44 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t38, ptr %t44
  br label %reuse.in_place.end.53
reuse.in_place.end.53:
  br label %reuse.join.52
reuse.copy.51:
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 47 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t6, ptr %t58
  call void @__inc_ref(ptr %t38)
  %t59 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t38, ptr %t59
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.54
reuse.copy.end.54:
  br label %reuse.join.52
reuse.join.52:
  %t60 = phi ptr [ %t5, %reuse.in_place.end.53 ], [ %t55, %reuse.copy.end.54 ]
  call void @__inc_ref(ptr %t40)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t40)
  store ptr %t40, ptr %t3
  store ptr %t60, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t61 = load ptr, ptr %t2
  ret ptr %t61
}

define internal ptr @v__apply__df__rowmono_0_bindIO_16(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_bindIO_20(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.19 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t15
  %t16 = call ptr @v__apply__df_bindIO_20(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.17:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t18 = call ptr @v__apply__df_bindIO_20(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = getelementptr ptr, ptr %t5, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t30 = getelementptr i8, ptr %t5, i64 -8
  %t31 = load i32, ptr %t30
  %t32 = icmp eq i32 %t31, 1
  br i1 %t32, label %reuse.in_place.33, label %reuse.copy.34
reuse.in_place.33:
  %t24 = getelementptr ptr, ptr %t5, i32 2
  %t25 = load ptr, ptr %t24
  call void @__free_recursive(ptr %t25)
  %t28 = inttoptr i64 49 to ptr
  %t29 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t26
  %t27 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t21, ptr %t27
  br label %reuse.in_place.end.36
reuse.in_place.end.36:
  br label %reuse.join.35
reuse.copy.34:
  %t38 = call ptr @__alloc(i64 24, i32 2)
  %t39 = inttoptr i64 49 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t6)
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t6, ptr %t41
  call void @__inc_ref(ptr %t21)
  %t42 = getelementptr ptr, ptr %t38, i32 2
  store ptr %t21, ptr %t42
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.37
reuse.copy.end.37:
  br label %reuse.join.35
reuse.join.35:
  %t43 = phi ptr [ %t5, %reuse.in_place.end.36 ], [ %t38, %reuse.copy.end.37 ]
  call void @__inc_ref(ptr %t23)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t23)
  store ptr %t23, ptr %t3
  store ptr %t43, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t44 = load ptr, ptr %t2
  ret ptr %t44
}

define internal ptr @v__apply__df_bindIO_20(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_4_bindIO_24(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.24 i64 7, label %tco.case.arm.7.36 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 25 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 30 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v__cps__lift_42(ptr %t12, ptr %t19)
  %t23 = call ptr @v__apply__df__rowmono_4_bindIO_24(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__inc_ref(ptr %t6)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 6 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 2252990199 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t26)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t26, ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  %t35 = call ptr @v__apply__df__rowmono_4_bindIO_24(ptr %t6, ptr %t27)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t35, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.36:
  %t37 = getelementptr ptr, ptr %t5, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t47 = getelementptr i8, ptr %t5, i64 -8
  %t48 = load i32, ptr %t47
  %t49 = icmp eq i32 %t48, 1
  br i1 %t49, label %reuse.in_place.50, label %reuse.copy.51
reuse.in_place.50:
  %t41 = getelementptr ptr, ptr %t5, i32 2
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t45 = inttoptr i64 51 to ptr
  %t46 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t43 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t43
  %t44 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t38, ptr %t44
  br label %reuse.in_place.end.53
reuse.in_place.end.53:
  br label %reuse.join.52
reuse.copy.51:
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 51 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t6, ptr %t58
  call void @__inc_ref(ptr %t38)
  %t59 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t38, ptr %t59
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.54
reuse.copy.end.54:
  br label %reuse.join.52
reuse.join.52:
  %t60 = phi ptr [ %t5, %reuse.in_place.end.53 ], [ %t55, %reuse.copy.end.54 ]
  call void @__inc_ref(ptr %t40)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t40)
  store ptr %t40, ptr %t3
  store ptr %t60, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t61 = load ptr, ptr %t2
  ret ptr %t61
}

define internal ptr @v__apply__df__rowmono_4_bindIO_24(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_8_bindIO_28(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.23 i64 7, label %tco.case.arm.7.35 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 5 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 32 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @v__cps__lift_46(ptr %t12, ptr %t18)
  %t22 = call ptr @v__apply__df__rowmono_8_bindIO_28(ptr %t6, ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t22, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.23:
  %t24 = getelementptr ptr, ptr %t5, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t6)
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 6 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 925038822 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t25)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t25, ptr %t32
  %t33 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t33
  %t34 = call ptr @v__apply__df__rowmono_8_bindIO_28(ptr %t6, ptr %t26)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t34, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.35:
  %t36 = getelementptr ptr, ptr %t5, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = getelementptr ptr, ptr %t5, i32 2
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t46 = getelementptr i8, ptr %t5, i64 -8
  %t47 = load i32, ptr %t46
  %t48 = icmp eq i32 %t47, 1
  br i1 %t48, label %reuse.in_place.49, label %reuse.copy.50
reuse.in_place.49:
  %t40 = getelementptr ptr, ptr %t5, i32 2
  %t41 = load ptr, ptr %t40
  call void @__free_recursive(ptr %t41)
  %t44 = inttoptr i64 53 to ptr
  %t45 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %t6)
  %t42 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t42
  %t43 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t37, ptr %t43
  br label %reuse.in_place.end.52
reuse.in_place.end.52:
  br label %reuse.join.51
reuse.copy.50:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 53 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t6)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t6, ptr %t57
  call void @__inc_ref(ptr %t37)
  %t58 = getelementptr ptr, ptr %t54, i32 2
  store ptr %t37, ptr %t58
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.53
reuse.copy.end.53:
  br label %reuse.join.51
reuse.join.51:
  %t59 = phi ptr [ %t5, %reuse.in_place.end.52 ], [ %t54, %reuse.copy.end.53 ]
  call void @__inc_ref(ptr %t39)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t39)
  store ptr %t39, ptr %t3
  store ptr %t59, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t60 = load ptr, ptr %t2
  ret ptr %t60
}

define internal ptr @v__apply__df__rowmono_8_bindIO_28(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_8_bindIO_32(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.24 i64 7, label %tco.case.arm.7.36 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 24 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 32 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v__cps__lift_46(ptr %t12, ptr %t19)
  %t23 = call ptr @v__apply__df__rowmono_8_bindIO_32(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__inc_ref(ptr %t6)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 6 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 925038822 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t26)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t26, ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  %t35 = call ptr @v__apply__df__rowmono_8_bindIO_32(ptr %t6, ptr %t27)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t35, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.36:
  %t37 = getelementptr ptr, ptr %t5, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t47 = getelementptr i8, ptr %t5, i64 -8
  %t48 = load i32, ptr %t47
  %t49 = icmp eq i32 %t48, 1
  br i1 %t49, label %reuse.in_place.50, label %reuse.copy.51
reuse.in_place.50:
  %t41 = getelementptr ptr, ptr %t5, i32 2
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t45 = inttoptr i64 55 to ptr
  %t46 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t43 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t43
  %t44 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t38, ptr %t44
  br label %reuse.in_place.end.53
reuse.in_place.end.53:
  br label %reuse.join.52
reuse.copy.51:
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 55 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t6, ptr %t58
  call void @__inc_ref(ptr %t38)
  %t59 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t38, ptr %t59
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.54
reuse.copy.end.54:
  br label %reuse.join.52
reuse.join.52:
  %t60 = phi ptr [ %t5, %reuse.in_place.end.53 ], [ %t55, %reuse.copy.end.54 ]
  call void @__inc_ref(ptr %t40)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t40)
  store ptr %t40, ptr %t3
  store ptr %t60, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t61 = load ptr, ptr %t2
  ret ptr %t61
}

define internal ptr @v__apply__df__rowmono_8_bindIO_32(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_bindIO_36(ptr %v_io, ptr %v__k) {
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
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 27 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t18
  %t19 = call ptr @v__apply__df_bindIO_36(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.20:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t21 = call ptr @v__apply__df_bindIO_36(ptr %t6, ptr %t5)
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
  %t31 = inttoptr i64 57 to ptr
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
  %t42 = inttoptr i64 57 to ptr
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

define internal ptr @v__apply__df_bindIO_36(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_12_bindIO_40(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.23 i64 7, label %tco.case.arm.7.25 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 5 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 34 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @v__cps__lift_50(ptr %t12, ptr %t18)
  %t22 = call ptr @v__apply__df__rowmono_12_bindIO_40(ptr %t6, ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t22, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.23:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t24 = call ptr @v__apply__df__rowmono_12_bindIO_40(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t36 = getelementptr i8, ptr %t5, i64 -8
  %t37 = load i32, ptr %t36
  %t38 = icmp eq i32 %t37, 1
  br i1 %t38, label %reuse.in_place.39, label %reuse.copy.40
reuse.in_place.39:
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__free_recursive(ptr %t31)
  %t34 = inttoptr i64 59 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t6)
  %t32 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t33
  br label %reuse.in_place.end.42
reuse.in_place.end.42:
  br label %reuse.join.41
reuse.copy.40:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 59 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t27)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t27, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.43
reuse.copy.end.43:
  br label %reuse.join.41
reuse.join.41:
  %t49 = phi ptr [ %t5, %reuse.in_place.end.42 ], [ %t44, %reuse.copy.end.43 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t50 = load ptr, ptr %t2
  ret ptr %t50
}

define internal ptr @v__apply__df__rowmono_12_bindIO_40(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_16_bindIO_44(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.23 i64 7, label %tco.case.arm.7.35 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 5 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 36 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @v__cps__lift_54(ptr %t12, ptr %t18)
  %t22 = call ptr @v__apply__df__rowmono_16_bindIO_44(ptr %t6, ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t22, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.23:
  %t24 = getelementptr ptr, ptr %t5, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t6)
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 6 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 925038822 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t25)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t25, ptr %t32
  %t33 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t33
  %t34 = call ptr @v__apply__df__rowmono_16_bindIO_44(ptr %t6, ptr %t26)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t34, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.35:
  %t36 = getelementptr ptr, ptr %t5, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = getelementptr ptr, ptr %t5, i32 2
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t46 = getelementptr i8, ptr %t5, i64 -8
  %t47 = load i32, ptr %t46
  %t48 = icmp eq i32 %t47, 1
  br i1 %t48, label %reuse.in_place.49, label %reuse.copy.50
reuse.in_place.49:
  %t40 = getelementptr ptr, ptr %t5, i32 2
  %t41 = load ptr, ptr %t40
  call void @__free_recursive(ptr %t41)
  %t44 = inttoptr i64 61 to ptr
  %t45 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %t6)
  %t42 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t42
  %t43 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t37, ptr %t43
  br label %reuse.in_place.end.52
reuse.in_place.end.52:
  br label %reuse.join.51
reuse.copy.50:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 61 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t6)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t6, ptr %t57
  call void @__inc_ref(ptr %t37)
  %t58 = getelementptr ptr, ptr %t54, i32 2
  store ptr %t37, ptr %t58
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.53
reuse.copy.end.53:
  br label %reuse.join.51
reuse.join.51:
  %t59 = phi ptr [ %t5, %reuse.in_place.end.52 ], [ %t54, %reuse.copy.end.53 ]
  call void @__inc_ref(ptr %t39)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t39)
  store ptr %t39, ptr %t3
  store ptr %t59, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t60 = load ptr, ptr %t2
  ret ptr %t60
}

define internal ptr @v__apply__df__rowmono_16_bindIO_44(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_16_bindIO_48(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.21 i64 7, label %tco.case.arm.7.33 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 8, i32 0)
  %t17 = inttoptr i64 36 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @v__cps__lift_54(ptr %t12, ptr %t16)
  %t20 = call ptr @v__apply__df__rowmono_16_bindIO_48(ptr %t6, ptr %t19)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t20, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.21:
  %t22 = getelementptr ptr, ptr %t5, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t6)
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 6 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 925038822 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t23)
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t23, ptr %t30
  %t31 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t27, ptr %t31
  %t32 = call ptr @v__apply__df__rowmono_16_bindIO_48(ptr %t6, ptr %t24)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t32, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.33:
  %t34 = getelementptr ptr, ptr %t5, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = getelementptr ptr, ptr %t5, i32 2
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t44 = getelementptr i8, ptr %t5, i64 -8
  %t45 = load i32, ptr %t44
  %t46 = icmp eq i32 %t45, 1
  br i1 %t46, label %reuse.in_place.47, label %reuse.copy.48
reuse.in_place.47:
  %t38 = getelementptr ptr, ptr %t5, i32 2
  %t39 = load ptr, ptr %t38
  call void @__free_recursive(ptr %t39)
  %t42 = inttoptr i64 63 to ptr
  %t43 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t6)
  %t40 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t40
  %t41 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t35, ptr %t41
  br label %reuse.in_place.end.50
reuse.in_place.end.50:
  br label %reuse.join.49
reuse.copy.48:
  %t52 = call ptr @__alloc(i64 24, i32 2)
  %t53 = inttoptr i64 63 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  call void @__inc_ref(ptr %t6)
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t6, ptr %t55
  call void @__inc_ref(ptr %t35)
  %t56 = getelementptr ptr, ptr %t52, i32 2
  store ptr %t35, ptr %t56
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.51
reuse.copy.end.51:
  br label %reuse.join.49
reuse.join.49:
  %t57 = phi ptr [ %t5, %reuse.in_place.end.50 ], [ %t52, %reuse.copy.end.51 ]
  call void @__inc_ref(ptr %t37)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t37)
  store ptr %t37, ptr %t3
  store ptr %t57, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t58 = load ptr, ptr %t2
  ret ptr %t58
}

define internal ptr @v__apply__df__rowmono_16_bindIO_48(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_12_bindIO_52(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.24 i64 7, label %tco.case.arm.7.26 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 24 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 34 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v__cps__lift_50(ptr %t12, ptr %t19)
  %t23 = call ptr @v__apply__df__rowmono_12_bindIO_52(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.24:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t25 = call ptr @v__apply__df__rowmono_12_bindIO_52(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t25, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.26:
  %t27 = getelementptr ptr, ptr %t5, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = getelementptr ptr, ptr %t5, i32 2
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t37 = getelementptr i8, ptr %t5, i64 -8
  %t38 = load i32, ptr %t37
  %t39 = icmp eq i32 %t38, 1
  br i1 %t39, label %reuse.in_place.40, label %reuse.copy.41
reuse.in_place.40:
  %t31 = getelementptr ptr, ptr %t5, i32 2
  %t32 = load ptr, ptr %t31
  call void @__free_recursive(ptr %t32)
  %t35 = inttoptr i64 65 to ptr
  %t36 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t33
  %t34 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t28, ptr %t34
  br label %reuse.in_place.end.43
reuse.in_place.end.43:
  br label %reuse.join.42
reuse.copy.41:
  %t45 = call ptr @__alloc(i64 24, i32 2)
  %t46 = inttoptr i64 65 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t6)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t6, ptr %t48
  call void @__inc_ref(ptr %t28)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t28, ptr %t49
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.44
reuse.copy.end.44:
  br label %reuse.join.42
reuse.join.42:
  %t50 = phi ptr [ %t5, %reuse.in_place.end.43 ], [ %t45, %reuse.copy.end.44 ]
  call void @__inc_ref(ptr %t30)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t30)
  store ptr %t30, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t51 = load ptr, ptr %t2
  ret ptr %t51
}

define internal ptr @v__apply__df__rowmono_12_bindIO_52(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_handleErrorIO_56(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_56(ptr %t6, ptr %t5)
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
  %t26 = call ptr @v__apply__df_handleErrorIO_56(ptr %t6, ptr %t14)
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
  %t36 = inttoptr i64 67 to ptr
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
  %t47 = inttoptr i64 67 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_56(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_60(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 69 to ptr
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
  %t49 = inttoptr i64 69 to ptr
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

define internal ptr @v__apply__df_andThenIO_60(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_mapIO_64(ptr %v_io, ptr %v__k) {
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
  %t19 = call ptr @v__apply__df_mapIO_64(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.20:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t21 = call ptr @v__apply__df_mapIO_64(ptr %t6, ptr %t5)
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
  %t31 = inttoptr i64 71 to ptr
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
  %t42 = inttoptr i64 71 to ptr
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

define internal ptr @v__apply__df_mapIO_64(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_handleErrorIO_68(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_68(ptr %t6, ptr %t5)
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
  %t50 = call ptr @v__apply__df_handleErrorIO_68(ptr %t6, ptr %t49)
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
  %t60 = inttoptr i64 73 to ptr
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
  %t71 = inttoptr i64 73 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_68(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_handleErrorIO_72(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_72(ptr %t6, ptr %t5)
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
  %t28 = call ptr @v__apply__df_handleErrorIO_72(ptr %t6, ptr %t14)
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
  %t38 = inttoptr i64 75 to ptr
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
  %t49 = inttoptr i64 75 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_72(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_handleErrorIO_76(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_76(ptr %t6, ptr %t5)
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
  %t52 = call ptr @v__apply__df_handleErrorIO_76(ptr %t6, ptr %t51)
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
  %t62 = inttoptr i64 77 to ptr
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
  %t73 = inttoptr i64 77 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_76(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_20_andThenIO_80(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_20_andThenIO_80(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_20_andThenIO_80(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 79 to ptr
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
  %t49 = inttoptr i64 79 to ptr
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

define internal ptr @v__apply__df__rowmono_20_andThenIO_80(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_handleErrorIO_84(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_84(ptr %t6, ptr %t5)
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
  %t50 = call ptr @v__apply__df_handleErrorIO_84(ptr %t6, ptr %t49)
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
  %t60 = inttoptr i64 81 to ptr
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
  %t71 = inttoptr i64 81 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_84(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_21_andThenIO_88(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_21_andThenIO_88(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_21_andThenIO_88(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 83 to ptr
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
  %t49 = inttoptr i64 83 to ptr
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

define internal ptr @v__apply__df__rowmono_21_andThenIO_88(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_handleErrorIO_92(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_92(ptr %t6, ptr %t5)
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
  %t74 = call ptr @v__apply__df_handleErrorIO_92(ptr %t6, ptr %t73)
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
  %t84 = inttoptr i64 85 to ptr
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
  %t95 = inttoptr i64 85 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_92(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_22_andThenIO_96(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_22_andThenIO_96(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_22_andThenIO_96(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 87 to ptr
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
  %t49 = inttoptr i64 87 to ptr
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

define internal ptr @v__apply__df__rowmono_22_andThenIO_96(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_handleErrorIO_100(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_100(ptr %t6, ptr %t5)
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
  %t90 = call ptr @v__apply__df_handleErrorIO_100(ptr %t6, ptr %t89)
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
  %t100 = inttoptr i64 89 to ptr
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
  %t111 = inttoptr i64 89 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_100(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df__rowmono_23_andThenIO_104(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_23_andThenIO_104(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_23_andThenIO_104(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 91 to ptr
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
  %t49 = inttoptr i64 91 to ptr
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

define internal ptr @v__apply__df__rowmono_23_andThenIO_104(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_108(ptr %v_io, ptr %v__k) {
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
  %t24 = call ptr @v__apply__df_andThenIO_108(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.25:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t26 = call ptr @v__apply__df_andThenIO_108(ptr %t6, ptr %t5)
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
  %t36 = inttoptr i64 93 to ptr
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
  %t47 = inttoptr i64 93 to ptr
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

define internal ptr @v__apply__df_andThenIO_108(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_112(ptr %v_io, ptr %v__df_andThenIO_112_cap0_0, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__df_andThenIO_112_cap0_0, ptr %t4
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
  %t14 = call ptr @v__apply__df_andThenIO_112(ptr %t8, ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.15:
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t6)
  %t16 = call ptr @v__apply__df_andThenIO_112(ptr %t8, ptr %t6)
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
  %t26 = inttoptr i64 95 to ptr
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
  %t37 = inttoptr i64 95 to ptr
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

define internal ptr @v__apply__df_andThenIO_112(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_116(ptr %v_io, ptr %v__k) {
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
  %t24 = call ptr @v__apply__df_andThenIO_116(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.25:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t26 = call ptr @v__apply__df_andThenIO_116(ptr %t6, ptr %t5)
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
  %t36 = inttoptr i64 97 to ptr
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
  %t47 = inttoptr i64 97 to ptr
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

define internal ptr @v__apply__df_andThenIO_116(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_120(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wOk()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 90 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_23_andThenIO_104(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 88 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_100(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_120(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_120(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 99 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 99 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_120(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_124(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wE3()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 90 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_23_andThenIO_104(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 88 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_100(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_124(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_124(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 101 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 101 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_124(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_128(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wE2str()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 90 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_23_andThenIO_104(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 88 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_100(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_128(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_128(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 103 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 103 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_128(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__cps__df_andThenIO_132(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wE1()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 90 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_23_andThenIO_104(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 88 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_100(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_132(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_132(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 105 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 105 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_132(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 104, label %tco.case.arm.104.11 i64 105, label %tco.case.arm.105.12 ]
tco.case.arm.104.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.105.12:
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

define internal ptr @v__cps__df_andThenIO_136(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idem2Second()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 72 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_68(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_136(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_136(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 107 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 107 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_136(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 106, label %tco.case.arm.106.11 i64 107, label %tco.case.arm.107.12 ]
tco.case.arm.106.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.107.12:
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

define internal ptr @v__cps__df_andThenIO_140(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idem2First()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 72 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_68(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_140(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_140(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 109 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 109 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_140(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 108, label %tco.case.arm.108.11 i64 109, label %tco.case.arm.109.12 ]
tco.case.arm.108.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.109.12:
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

define internal ptr @v__cps__df_andThenIO_144(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idemE2()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 66 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_56(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_144(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_144(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 111 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 111 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_144(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 110, label %tco.case.arm.110.11 i64 111, label %tco.case.arm.111.12 ]
tco.case.arm.110.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.111.12:
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

define internal ptr @v__cps__df_andThenIO_148(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idemE1()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 66 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_56(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_148(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_148(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 113 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 113 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_148(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 112, label %tco.case.arm.112.11 i64 113, label %tco.case.arm.113.12 ]
tco.case.arm.112.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.113.12:
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

define internal ptr @v__cps__df_andThenIO_152(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoOk()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 86 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_22_andThenIO_96(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 84 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_92(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_152(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_152(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 115 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 115 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_152(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 114, label %tco.case.arm.114.11 i64 115, label %tco.case.arm.115.12 ]
tco.case.arm.114.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.115.12:
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

define internal ptr @v__cps__df_andThenIO_156(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoE2()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 86 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_22_andThenIO_96(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 84 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_92(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_156(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_156(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 117 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 117 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_156(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 116, label %tco.case.arm.116.11 i64 117, label %tco.case.arm.117.12 ]
tco.case.arm.116.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.117.12:
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

define internal ptr @v__cps__df_andThenIO_160(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoSecond()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 86 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_22_andThenIO_96(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 84 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_92(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_160(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_160(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 119 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 119 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_160(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 118, label %tco.case.arm.118.11 i64 119, label %tco.case.arm.119.12 ]
tco.case.arm.118.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.119.12:
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

define internal ptr @v__cps__df_andThenIO_164(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoFirst()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 86 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_22_andThenIO_96(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 84 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_92(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_164(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_164(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 121 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 121 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_164(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 120, label %tco.case.arm.120.11 i64 121, label %tco.case.arm.121.12 ]
tco.case.arm.120.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.121.12:
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

define internal ptr @v__cps__df_andThenIO_168(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_abE2()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 82 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_21_andThenIO_88(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 80 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_84(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_168(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_168(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 123 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 123 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_168(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 122, label %tco.case.arm.122.11 i64 123, label %tco.case.arm.123.12 ]
tco.case.arm.122.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.123.12:
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

define internal ptr @v__cps__df_andThenIO_172(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_abE1()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 82 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_21_andThenIO_88(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 80 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_84(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_172(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_172(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 125 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 125 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_172(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 124, label %tco.case.arm.124.11 i64 125, label %tco.case.arm.125.12 ]
tco.case.arm.124.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.125.12:
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

define internal ptr @v__cps__df_andThenIO_176(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strIdem()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 74 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_72(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_176(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_176(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 127 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 127 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_176(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 126, label %tco.case.arm.126.11 i64 127, label %tco.case.arm.127.12 ]
tco.case.arm.126.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.127.12:
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

define internal ptr @v__cps__df_andThenIO_180(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strE2()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 78 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_20_andThenIO_80(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 76 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_76(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_180(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_180(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 129 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 129 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_180(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 128, label %tco.case.arm.128.11 i64 129, label %tco.case.arm.129.12 ]
tco.case.arm.128.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.129.12:
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

define internal ptr @v__cps__df_andThenIO_184(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strE1()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 78 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_20_andThenIO_80(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 76 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_76(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_184(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_184(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 131 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 131 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_184(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 130, label %tco.case.arm.130.11 i64 131, label %tco.case.arm.131.12 ]
tco.case.arm.130.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.131.12:
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

define internal ptr @v__cps__df_andThenIO_188(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strOk()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 78 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df__rowmono_20_andThenIO_80(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 76 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_76(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_188(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_188(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 133 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 133 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_188(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 132, label %tco.case.arm.132.11 i64 133, label %tco.case.arm.133.12 ]
tco.case.arm.132.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.133.12:
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

define internal ptr @v__cps__df_andThenIO_192(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.46 i64 7, label %tco.case.arm.7.48 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_pureNever()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 94 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 92 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_108(ptr %t40, ptr %t41)
  %t45 = call ptr @v__apply__df_andThenIO_192(ptr %t6, ptr %t44)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t45, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.46:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t47 = call ptr @v__apply__df_andThenIO_192(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t47, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.48:
  %t49 = getelementptr ptr, ptr %t5, i32 1
  %t50 = load ptr, ptr %t49
  %t51 = getelementptr ptr, ptr %t5, i32 2
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr i8, ptr %t5, i64 -8
  %t60 = load i32, ptr %t59
  %t61 = icmp eq i32 %t60, 1
  br i1 %t61, label %reuse.in_place.62, label %reuse.copy.63
reuse.in_place.62:
  %t53 = getelementptr ptr, ptr %t5, i32 2
  %t54 = load ptr, ptr %t53
  call void @__free_recursive(ptr %t54)
  %t57 = inttoptr i64 135 to ptr
  %t58 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t6)
  %t55 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t55
  %t56 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t50, ptr %t56
  br label %reuse.in_place.end.65
reuse.in_place.end.65:
  br label %reuse.join.64
reuse.copy.63:
  %t67 = call ptr @__alloc(i64 24, i32 2)
  %t68 = inttoptr i64 135 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t6)
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t6, ptr %t70
  call void @__inc_ref(ptr %t50)
  %t71 = getelementptr ptr, ptr %t67, i32 2
  store ptr %t50, ptr %t71
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.66
reuse.copy.end.66:
  br label %reuse.join.64
reuse.join.64:
  %t72 = phi ptr [ %t5, %reuse.in_place.end.65 ], [ %t67, %reuse.copy.end.66 ]
  call void @__inc_ref(ptr %t52)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t52)
  store ptr %t52, ptr %t3
  store ptr %t72, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t73 = load ptr, ptr %t2
  ret ptr %t73
}

define internal ptr @v__apply__df_andThenIO_192(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 134, label %tco.case.arm.134.11 i64 135, label %tco.case.arm.135.12 ]
tco.case.arm.134.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.135.12:
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

define internal ptr @v__cps__df_andThenIO_196(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_nevRightE1()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 66 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_56(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_196(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_196(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 137 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 137 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_196(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 136, label %tco.case.arm.136.11 i64 137, label %tco.case.arm.137.12 ]
tco.case.arm.136.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.137.12:
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

define internal ptr @v__cps__df_andThenIO_200(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_nevRightOk()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 66 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_56(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_200(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_200(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 139 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 139 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_200(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 138, label %tco.case.arm.138.11 i64 139, label %tco.case.arm.139.12 ]
tco.case.arm.138.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.139.12:
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

define internal ptr @v__cps__df_andThenIO_204(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.50 i64 7, label %tco.case.arm.7.52 ]
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
  %t25 = inttoptr i64 96 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_116(ptr %t12, ptr %t24)
  %t28 = call ptr @v_nevFail()
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 70 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_mapIO_64(ptr %t28, ptr %t29)
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 68 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @v__cps__df_andThenIO_60(ptr %t32, ptr %t33)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 66 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__cps__df_handleErrorIO_56(ptr %t36, ptr %t37)
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 94 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_112(ptr %t27, ptr %t40, ptr %t41)
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 92 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_108(ptr %t44, ptr %t45)
  %t49 = call ptr @v__apply__df_andThenIO_204(ptr %t6, ptr %t48)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.50:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t51 = call ptr @v__apply__df_andThenIO_204(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__free_recursive(ptr %t58)
  %t61 = inttoptr i64 141 to ptr
  %t62 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t59 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t59
  %t60 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t60
  br label %reuse.in_place.end.69
reuse.in_place.end.69:
  br label %reuse.join.68
reuse.copy.67:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 141 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t6)
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t6, ptr %t74
  call void @__inc_ref(ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t54, ptr %t75
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.70
reuse.copy.end.70:
  br label %reuse.join.68
reuse.join.68:
  %t76 = phi ptr [ %t5, %reuse.in_place.end.69 ], [ %t71, %reuse.copy.end.70 ]
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t76, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
}

define internal ptr @v__apply__df_andThenIO_204(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 140, label %tco.case.arm.140.11 i64 141, label %tco.case.arm.141.12 ]
tco.case.arm.140.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.141.12:
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
