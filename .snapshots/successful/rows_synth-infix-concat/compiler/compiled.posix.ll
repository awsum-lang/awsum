; External C declarations
declare ptr @malloc(i64)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant {i32, i32} { i32 0, i32 0 }
@.cli_arg = internal global ptr null

@.str.0 = private unnamed_addr constant {i32, i32, [16 x i8]} { i32 16, i32 16, [16 x i8] c"0123456789abcdef" }
@.str.1 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"string-too-long" }
@.str.2 = private unnamed_addr constant {i32, i32, [9 x i8]} { i32 9, i32 9, [9 x i8] c"underflow" }
@.str.3 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 4, [4 x i8] c"done" }

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
  %stl = call ptr @malloc(i64 8)
  %stl_tag = inttoptr i64 15 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  ret ptr %left
ok:
  %ba64 = zext i32 %ba to i64
  %bb64 = zext i32 %bb to i64
  %bsum64 = add i64 %ba64, %bb64
  %alloc64 = add i64 %bsum64, 8
  %buf = call ptr @malloc(i64 %alloc64)
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
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  ret ptr %right
}


define internal ptr @__print(ptr %s) {
  %byte_count = load i32, ptr %s
  %byte_count_64 = zext i32 %byte_count to i64
  %payload = getelementptr i8, ptr %s, i64 8
  call i64 @write(i32 1, ptr %payload, i64 %byte_count_64)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @__predInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
  %oe = call ptr @malloc(i64 8)
  %oe_tag = inttoptr i64 13 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  ret ptr %left
ok:
  %newv = sub i32 %v, 1
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @__eqInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
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
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.12:
  %t13 = getelementptr ptr, ptr %t4, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t4, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @__print(ptr %t14)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 0, label %tco.case.arm.0.22 ]
tco.case.arm.0.22:
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

define internal ptr @v_double(ptr %v_n, ptr %v_s) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t4 = alloca ptr
  store ptr %v_s, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = call ptr @malloc(i64 4)
  store i32 0, ptr %t7
  %t8 = call ptr @__eqInt32(ptr %t5, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.18 ]
tco.case.arm.1.13:
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t6, ptr %t17
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.18:
  %t19 = call ptr @__predInt32(ptr %t5)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %tco.case.default.23 [ i64 3, label %tco.case.arm.3.24 i64 4, label %tco.case.arm.4.35 ]
tco.case.arm.3.24:
  %t25 = getelementptr ptr, ptr %t19, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 16)
  %t28 = inttoptr i64 3 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 3768445577 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t26, ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.35:
  %t36 = getelementptr ptr, ptr %t19, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = call ptr @__concat(ptr %t6, ptr %t6)
  %t39 = getelementptr ptr, ptr %t38, i32 0
  %t40 = load ptr, ptr %t39
  %t41 = ptrtoint ptr %t40 to i64
  switch i64 %t41, label %tco.case.default.42 [ i64 3, label %tco.case.arm.3.43 i64 4, label %tco.case.arm.4.54 ]
tco.case.arm.3.43:
  %t44 = getelementptr ptr, ptr %t38, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = call ptr @malloc(i64 16)
  %t50 = inttoptr i64 589989748 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t45, ptr %t52
  %t53 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t53
  store ptr %t46, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.54:
  %t55 = getelementptr ptr, ptr %t38, i32 1
  %t56 = load ptr, ptr %t55
  store ptr %t37, ptr %t3
  store ptr %t56, ptr %t4
  br label %tco.loop.0
tco.case.default.42:
  unreachable
tco.case.default.23:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t57 = load ptr, ptr %t2
  ret ptr %t57
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 4)
  store i32 24, ptr %t0
  %t1 = call ptr @v_double(ptr %t0, ptr @.str.0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 3, label %case.arm.3.7 i64 4, label %case.arm.4.49 ]
case.arm.3.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %case.default.14 [ i64 589989748, label %case.arm.589989748.16 i64 3768445577, label %case.arm.3768445577.32 ]
case.arm.589989748.16:
  %t18 = getelementptr ptr, ptr %t10, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 24)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr @.str.1, ptr %t23
  %t24 = call ptr @malloc(i64 16)
  %t25 = inttoptr i64 5 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @malloc(i64 8)
  %t28 = inttoptr i64 0 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t27, ptr %t30
  %t31 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t24, ptr %t31
  br label %case.end.589989748.17
case.end.589989748.17:
  br label %case.join.15
case.arm.3768445577.32:
  %t34 = getelementptr ptr, ptr %t10, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = call ptr @malloc(i64 24)
  %t37 = inttoptr i64 7 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr @.str.2, ptr %t39
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 5 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = call ptr @malloc(i64 8)
  %t44 = inttoptr i64 0 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t43, ptr %t46
  %t47 = getelementptr ptr, ptr %t36, i32 2
  store ptr %t40, ptr %t47
  br label %case.end.3768445577.33
case.end.3768445577.33:
  br label %case.join.15
case.default.14:
  unreachable
case.join.15:
  %t48 = phi ptr [%t20, %case.end.589989748.17], [%t36, %case.end.3768445577.33]
  br label %case.end.3.8
case.end.3.8:
  br label %case.join.6
case.arm.4.49:
  %t51 = getelementptr ptr, ptr %t1, i32 1
  %t52 = load ptr, ptr %t51
  %t53 = call ptr @malloc(i64 24)
  %t54 = inttoptr i64 7 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr @.str.3, ptr %t56
  %t57 = call ptr @malloc(i64 16)
  %t58 = inttoptr i64 5 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = call ptr @malloc(i64 8)
  %t61 = inttoptr i64 0 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t63
  %t64 = getelementptr ptr, ptr %t53, i32 2
  store ptr %t57, ptr %t64
  br label %case.end.4.50
case.end.4.50:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t65 = phi ptr [%t48, %case.end.3.8], [%t53, %case.end.4.50]
  ret ptr %t65
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
  %input = phi ptr [%arg, %with_arg], [@.empty, %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
