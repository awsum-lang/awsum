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

@.str.0 = private unnamed_addr constant {i32, i32, [7 x i8]} { i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.1 = private unnamed_addr constant {i32, i32, [9 x i8]} { i32 9, i32 9, [9 x i8] c"Just True" }
@.str.2 = private unnamed_addr constant {i32, i32, [10 x i8]} { i32 10, i32 10, [10 x i8] c"Just False" }
@.str.3 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_whatsThat(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1454647603, label %case.arm.1454647603.5 ]
case.arm.1454647603.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 9, label %case.arm.9.14 i64 10, label %case.arm.10.20 ]
case.arm.9.14:
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 4 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t16, i32 1
  store ptr @.str.0, ptr %t19
  br label %case.end.9.15
case.end.9.15:
  br label %case.join.13
case.arm.10.20:
  %t22 = getelementptr ptr, ptr %t8, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 796142685, label %case.arm.796142685.29 ]
case.arm.796142685.29:
  %t31 = getelementptr ptr, ptr %t23, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = getelementptr ptr, ptr %t32, i32 0
  %t34 = load ptr, ptr %t33
  %t35 = ptrtoint ptr %t34 to i64
  switch i64 %t35, label %case.default.36 [ i64 1, label %case.arm.1.38 i64 2, label %case.arm.2.44 ]
case.arm.1.38:
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 4 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr @.str.1, ptr %t43
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.37
case.arm.2.44:
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 4 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr @.str.2, ptr %t49
  br label %case.end.2.45
case.end.2.45:
  br label %case.join.37
case.default.36:
  unreachable
case.join.37:
  %t50 = phi ptr [%t40, %case.end.1.39], [%t46, %case.end.2.45]
  br label %case.end.796142685.30
case.end.796142685.30:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t51 = phi ptr [%t50, %case.end.796142685.30]
  br label %case.end.10.21
case.end.10.21:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t52 = phi ptr [%t16, %case.end.9.15], [%t51, %case.end.10.21]
  br label %case.end.1454647603.6
case.end.1454647603.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t53 = phi ptr [%t52, %case.end.1454647603.6]
  ret ptr %t53
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1454647603 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 10 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 1 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = call ptr @v__lift_7(ptr %t3)
  %t11 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t10, ptr %t11
  %t12 = call ptr @v_whatsThat(ptr %t0)
  %t13 = call ptr @v__let_8(ptr %t12)
  ret ptr %t13
}

define internal ptr @v__lift_7(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 9, label %case.arm.9.5 i64 10, label %case.arm.10.10 ]
case.arm.9.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 9 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.9.6
case.end.9.6:
  br label %case.join.4
case.arm.10.10:
  %t12 = getelementptr ptr, ptr %v___input, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 10 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 796142685 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t13, ptr %t20
  %t21 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t21
  br label %case.end.10.11
case.end.10.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t7, %case.end.9.6], [%t14, %case.end.10.11]
  ret ptr %t22
}

define internal ptr @v__let_8(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.21 ]
case.arm.3.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 24)
  %t10 = inttoptr i64 7 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr @.str.3, ptr %t12
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 5 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @malloc(i64 8)
  %t17 = inttoptr i64 0 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t19
  %t20 = getelementptr ptr, ptr %t9, i32 2
  store ptr %t13, ptr %t20
  br label %case.end.3.6
case.end.3.6:
  br label %case.join.4
case.arm.4.21:
  %t23 = getelementptr ptr, ptr %v_res, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @malloc(i64 24)
  %t26 = inttoptr i64 7 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t24, ptr %t28
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 5 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 8)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t35
  %t36 = getelementptr ptr, ptr %t25, i32 2
  store ptr %t29, ptr %t36
  br label %case.end.4.22
case.end.4.22:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t37 = phi ptr [%t9, %case.end.3.6], [%t25, %case.end.4.22]
  ret ptr %t37
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
