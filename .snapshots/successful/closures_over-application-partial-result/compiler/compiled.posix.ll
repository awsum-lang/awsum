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

define internal ptr @v_inc(ptr %v_n) {
  ret ptr %v_n
}

define internal ptr @v_main() {
  %t0 = call ptr @v__df_identity_0()
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 9 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v__apply1(ptr %t0, ptr %t1)
  %t5 = call ptr @v__let_13(ptr %t4)
  ret ptr %t5
}

define internal ptr @v__let_13(ptr %v_g) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_g)
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t3
  %t4 = call ptr @v__apply1(ptr %v_g, ptr %t3)
  %t5 = call ptr @__showInt32(ptr %t4)
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t5, ptr %t6
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 5 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 8, i32 0)
  %t11 = inttoptr i64 0 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t7, ptr %t14
  call void @__free_recursive(ptr %v_g)
  ret ptr %t0
}

define internal ptr @v__df_identity_0() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  ret ptr %t0
}

define internal ptr @v__scc__apply1_applyOnce(ptr %v__args) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 11, label %tco.case.arm.11.9 i64 12, label %tco.case.arm.12.45 ]
tco.case.arm.11.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 8, label %tco.case.arm.8.18 i64 9, label %tco.case.arm.9.38 i64 10, label %tco.case.arm.10.40 ]
tco.case.arm.8.18:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr i8, ptr %t4, i64 -8
  %t22 = load i32, ptr %t21
  %t23 = icmp eq i32 %t22, 1
  br i1 %t23, label %reuse.in_place.24, label %reuse.copy.25
reuse.in_place.24:
  %t27 = getelementptr ptr, ptr %t4, i32 1
  %t28 = load ptr, ptr %t27
  call void @__free_recursive(ptr %t28)
  %t30 = inttoptr i64 12 to ptr
  %t31 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t20)
  %t29 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t20, ptr %t29
  br label %reuse.join.26
reuse.copy.25:
  %t32 = call ptr @__alloc(i64 24, i32 2)
  %t33 = inttoptr i64 12 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  call void @__inc_ref(ptr %t20)
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t20, ptr %t35
  call void @__inc_ref(ptr %t13)
  %t36 = getelementptr ptr, ptr %t32, i32 2
  store ptr %t13, ptr %t36
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.26
reuse.join.26:
  %t37 = phi ptr [ %t4, %reuse.in_place.24 ], [ %t32, %reuse.copy.25 ]
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t37, ptr %t3
  br label %tco.loop.0
tco.case.arm.9.38:
  call void @__inc_ref(ptr %t13)
  %t39 = call ptr @v_inc(ptr %t13)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t39, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.40:
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 8 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t13)
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t13, ptr %t44
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t41, ptr %t2
  br label %tco.exit.1
tco.case.default.17:
  unreachable
tco.case.arm.12.45:
  %t46 = getelementptr ptr, ptr %t4, i32 1
  %t47 = load ptr, ptr %t46
  %t48 = getelementptr ptr, ptr %t4, i32 2
  %t49 = load ptr, ptr %t48
  %t50 = getelementptr i8, ptr %t4, i64 -8
  %t51 = load i32, ptr %t50
  %t52 = icmp eq i32 %t51, 1
  br i1 %t52, label %reuse.in_place.53, label %reuse.copy.54
reuse.in_place.53:
  %t56 = inttoptr i64 11 to ptr
  %t57 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t56, ptr %t57
  br label %reuse.join.55
reuse.copy.54:
  %t58 = call ptr @__alloc(i64 24, i32 2)
  %t59 = inttoptr i64 11 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  call void @__inc_ref(ptr %t47)
  %t61 = getelementptr ptr, ptr %t58, i32 1
  store ptr %t47, ptr %t61
  call void @__inc_ref(ptr %t49)
  %t62 = getelementptr ptr, ptr %t58, i32 2
  store ptr %t49, ptr %t62
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.55
reuse.join.55:
  %t63 = phi ptr [ %t4, %reuse.in_place.53 ], [ %t58, %reuse.copy.54 ]
  store ptr %t63, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t64 = load ptr, ptr %t2
  ret ptr %t64
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 11 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1_applyOnce(ptr %t0)
  call void @__free_recursive(ptr %v__cl)
  call void @__free_recursive(ptr %v__arg0)
  ret ptr %t5
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
