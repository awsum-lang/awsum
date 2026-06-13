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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 8, label %case.arm.8.9 i64 9, label %case.arm.9.13 i64 10, label %case.arm.10.22 ]
case.arm.8.9:
  %t11 = getelementptr ptr, ptr %t0, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  br label %case.end.8.10
case.end.8.10:
  br label %case.join.8
case.arm.9.13:
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 8 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t19, ptr %t20
  call void @__inc_ref(ptr %t3)
  %t21 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t3, ptr %t21
  br label %case.end.9.14
case.end.9.14:
  br label %case.join.8
case.arm.10.22:
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 9 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  call void @__inc_ref(ptr %t3)
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t3, ptr %t27
  br label %case.end.10.23
case.end.10.23:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t28 = phi ptr [ %t12, %case.end.8.10 ], [ %t15, %case.end.9.14 ], [ %t24, %case.end.10.23 ]
  call void @__free_recursive(ptr %t3)
  call void @__free_recursive(ptr %t0)
  %t29 = call ptr @__alloc(i64 4, i32 0)
  store i32 8, ptr %t29
  %t30 = getelementptr ptr, ptr %t28, i32 0
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  switch i64 %t32, label %case.default.33 [ i64 8, label %case.arm.8.35 i64 9, label %case.arm.9.39 i64 10, label %case.arm.10.48 ]
case.arm.8.35:
  %t37 = getelementptr ptr, ptr %t28, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  br label %case.end.8.36
case.end.8.36:
  br label %case.join.34
case.arm.9.39:
  %t41 = call ptr @__alloc(i64 24, i32 2)
  %t42 = inttoptr i64 8 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t28, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t29)
  %t47 = getelementptr ptr, ptr %t41, i32 2
  store ptr %t29, ptr %t47
  br label %case.end.9.40
case.end.9.40:
  br label %case.join.34
case.arm.10.48:
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 9 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  call void @__inc_ref(ptr %t29)
  %t53 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t29, ptr %t53
  br label %case.end.10.49
case.end.10.49:
  br label %case.join.34
case.default.33:
  unreachable
case.join.34:
  %t54 = phi ptr [ %t38, %case.end.8.36 ], [ %t41, %case.end.9.40 ], [ %t50, %case.end.10.49 ]
  call void @__free_recursive(ptr %t29)
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 7 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @__alloc(i64 4, i32 0)
  store i32 9, ptr %t58
  %t59 = getelementptr ptr, ptr %t54, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %case.default.62 [ i64 8, label %case.arm.8.64 i64 9, label %case.arm.9.68 i64 10, label %case.arm.10.77 ]
case.arm.8.64:
  %t66 = getelementptr ptr, ptr %t54, i32 1
  %t67 = load ptr, ptr %t66
  call void @__inc_ref(ptr %t67)
  br label %case.end.8.65
case.end.8.65:
  br label %case.join.63
case.arm.9.68:
  %t70 = call ptr @__alloc(i64 24, i32 2)
  %t71 = inttoptr i64 8 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = getelementptr ptr, ptr %t54, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  %t75 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t74, ptr %t75
  call void @__inc_ref(ptr %t58)
  %t76 = getelementptr ptr, ptr %t70, i32 2
  store ptr %t58, ptr %t76
  br label %case.end.9.69
case.end.9.69:
  br label %case.join.63
case.arm.10.77:
  %t79 = call ptr @__alloc(i64 16, i32 1)
  %t80 = inttoptr i64 9 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  call void @__inc_ref(ptr %t58)
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t58, ptr %t82
  br label %case.end.10.78
case.end.10.78:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t83 = phi ptr [ %t67, %case.end.8.65 ], [ %t70, %case.end.9.69 ], [ %t79, %case.end.10.78 ]
  call void @__free_recursive(ptr %t58)
  %t84 = call ptr @__showInt32(ptr %t83)
  %t85 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t84, ptr %t85
  %t86 = call ptr @__alloc(i64 16, i32 1)
  %t87 = inttoptr i64 5 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  %t89 = call ptr @__alloc(i64 8, i32 0)
  %t90 = inttoptr i64 0 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  %t92 = getelementptr ptr, ptr %t86, i32 1
  store ptr %t89, ptr %t92
  %t93 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t86, ptr %t93
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t28)
  ret ptr %t55
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
