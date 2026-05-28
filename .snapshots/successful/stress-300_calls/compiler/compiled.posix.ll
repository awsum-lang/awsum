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
@.cli_argc = internal global i64 0
@.cli_argv = internal global ptr null

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"True" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"False" }

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


define internal ptr @v_and(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_a, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1, label %case.arm.1.4 i64 2, label %case.arm.2.5 ]
case.arm.1.4:
  call void @__free_recursive(ptr %v_a)
  ret ptr %v_b
case.arm.2.5:
  %t6 = call ptr @__alloc(i64 8, i32 0)
  %t7 = inttoptr i64 2 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  call void @__free_recursive(ptr %v_a)
  call void @__free_recursive(ptr %v_b)
  ret ptr %t6
case.default.3:
  unreachable
}

define internal ptr @v_showBool(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1, label %case.arm.1.4 i64 2, label %case.arm.2.5 ]
case.arm.1.4:
  call void @__free_recursive(ptr %v_b)
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
case.arm.2.5:
  call void @__free_recursive(ptr %v_b)
  ret ptr getelementptr inbounds (i8, ptr @.str.1, i64 12)
case.default.3:
  unreachable
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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @v_f1(ptr %t3)
  %t7 = call ptr @v_showBool(ptr %t6)
  %t8 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 16, i32 1)
  %t10 = inttoptr i64 5 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t15
  %t16 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t9, ptr %t16
  ret ptr %t0
}

define internal ptr @v_f1(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f2(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f2(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f3(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f3(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f4(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f4(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f5(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f5(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f6(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f6(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f7(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f7(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f8(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f8(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f9(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f9(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f10(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f10(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f11(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f11(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f12(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f12(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f13(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f13(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f14(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f14(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f15(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f15(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f16(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f16(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f17(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f17(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f18(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f18(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f19(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f19(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f20(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f20(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f21(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f21(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f22(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f22(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f23(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f23(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f24(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f24(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f25(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f25(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f26(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f26(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f27(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f27(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f28(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f28(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f29(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f29(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f30(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f30(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f31(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f31(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f32(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f32(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f33(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f33(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f34(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f34(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f35(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f35(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f36(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f36(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f37(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f37(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f38(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f38(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f39(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f39(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f40(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f40(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f41(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f41(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f42(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f42(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f43(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f43(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f44(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f44(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f45(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f45(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f46(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f46(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f47(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f47(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f48(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f48(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f49(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f49(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f50(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f50(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f51(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f51(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f52(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f52(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f53(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f53(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f54(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f54(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f55(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f55(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f56(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f56(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f57(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f57(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f58(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f58(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f59(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f59(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f60(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f60(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f61(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f61(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f62(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f62(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f63(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f63(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f64(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f64(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f65(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f65(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f66(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f66(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f67(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f67(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f68(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f68(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f69(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f69(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f70(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f70(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f71(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f71(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f72(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f72(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f73(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f73(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f74(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f74(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f75(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f75(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f76(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f76(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f77(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f77(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f78(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f78(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f79(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f79(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f80(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f80(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f81(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f81(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f82(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f82(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f83(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f83(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f84(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f84(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f85(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f85(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f86(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f86(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f87(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f87(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f88(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f88(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f89(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f89(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f90(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f90(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f91(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f91(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f92(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f92(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f93(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f93(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f94(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f94(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f95(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f95(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f96(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f96(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f97(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f97(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f98(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f98(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f99(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f99(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f100(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f100(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f101(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f101(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f102(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f102(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f103(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f103(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f104(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f104(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f105(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f105(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f106(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f106(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f107(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f107(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f108(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f108(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f109(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f109(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f110(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f110(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f111(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f111(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f112(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f112(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f113(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f113(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f114(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f114(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f115(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f115(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f116(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f116(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f117(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f117(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f118(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f118(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f119(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f119(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f120(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f120(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f121(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f121(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f122(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f122(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f123(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f123(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f124(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f124(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f125(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f125(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f126(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f126(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f127(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f127(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f128(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f128(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f129(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f129(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f130(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f130(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f131(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f131(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f132(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f132(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f133(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f133(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f134(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f134(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f135(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f135(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f136(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f136(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f137(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f137(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f138(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f138(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f139(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f139(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f140(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f140(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f141(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f141(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f142(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f142(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f143(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f143(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f144(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f144(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f145(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f145(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f146(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f146(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f147(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f147(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f148(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f148(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f149(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f149(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f150(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f150(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f151(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f151(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f152(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f152(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f153(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f153(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f154(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f154(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f155(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f155(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f156(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f156(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f157(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f157(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f158(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f158(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f159(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f159(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f160(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f160(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f161(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f161(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f162(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f162(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f163(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f163(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f164(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f164(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f165(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f165(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f166(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f166(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f167(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f167(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f168(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f168(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f169(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f169(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f170(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f170(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f171(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f171(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f172(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f172(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f173(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f173(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f174(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f174(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f175(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f175(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f176(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f176(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f177(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f177(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f178(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f178(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f179(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f179(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f180(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f180(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f181(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f181(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f182(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f182(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f183(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f183(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f184(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f184(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f185(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f185(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f186(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f186(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f187(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f187(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f188(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f188(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f189(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f189(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f190(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f190(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f191(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f191(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f192(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f192(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f193(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f193(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f194(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f194(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f195(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f195(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f196(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f196(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f197(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f197(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f198(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f198(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f199(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f199(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f200(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f200(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f201(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f201(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f202(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f202(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f203(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f203(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f204(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f204(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f205(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f205(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f206(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f206(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f207(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f207(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f208(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f208(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f209(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f209(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f210(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f210(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f211(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f211(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f212(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f212(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f213(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f213(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f214(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f214(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f215(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f215(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f216(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f216(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f217(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f217(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f218(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f218(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f219(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f219(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f220(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f220(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f221(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f221(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f222(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f222(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f223(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f223(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f224(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f224(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f225(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f225(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f226(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f226(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f227(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f227(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f228(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f228(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f229(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f229(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f230(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f230(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f231(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f231(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f232(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f232(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f233(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f233(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f234(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f234(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f235(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f235(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f236(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f236(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f237(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f237(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f238(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f238(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f239(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f239(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f240(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f240(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f241(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f241(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f242(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f242(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f243(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f243(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f244(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f244(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f245(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f245(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f246(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f246(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f247(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f247(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f248(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f248(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f249(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f249(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f250(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f250(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f251(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f251(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f252(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f252(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f253(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f253(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f254(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f254(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f255(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f255(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f256(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f256(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f257(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f257(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f258(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f258(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f259(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f259(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f260(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f260(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f261(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f261(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f262(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f262(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f263(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f263(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f264(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f264(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f265(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f265(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f266(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f266(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f267(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f267(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f268(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f268(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f269(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f269(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f270(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f270(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f271(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f271(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f272(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f272(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f273(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f273(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f274(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f274(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f275(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f275(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f276(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f276(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f277(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f277(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f278(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f278(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f279(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f279(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f280(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f280(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f281(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f281(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f282(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f282(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f283(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f283(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f284(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f284(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f285(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f285(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f286(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f286(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f287(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f287(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f288(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f288(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f289(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f289(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f290(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f290(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f291(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f291(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f292(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f292(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f293(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f293(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f294(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f294(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f295(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f295(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f296(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f296(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f297(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f297(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f298(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f298(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f299(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f299(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  %t4 = call ptr @v_f300(ptr %t3)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t4
}

define internal ptr @v_f300(ptr %v_acc) {
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_and(ptr %v_acc, ptr %t0)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t3
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
