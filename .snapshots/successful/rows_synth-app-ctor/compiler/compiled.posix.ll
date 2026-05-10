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

@.str.0 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"s" }
@.str.1 = private unnamed_addr constant {i32, i32, [5 x i8]} { i32 5, i32 5, [5 x i8] c"hello" }
@.str.2 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"n" }

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

define internal ptr @v_dispatch(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1615808600, label %case.arm.1615808600.5 ]
case.arm.1615808600.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  br label %case.end.1615808600.6
case.end.1615808600.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t9 = phi ptr [@.str.0, %case.end.1615808600.6]
  ret ptr %t9
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr @.str.1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 9, label %case.arm.9.9 i64 10, label %case.arm.10.23 ]
case.arm.9.9:
  %t11 = call ptr @malloc(i64 24)
  %t12 = inttoptr i64 7 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr @.str.2, ptr %t14
  %t15 = call ptr @malloc(i64 16)
  %t16 = inttoptr i64 5 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @malloc(i64 8)
  %t19 = inttoptr i64 0 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t21
  %t22 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t15, ptr %t22
  br label %case.end.9.10
case.end.9.10:
  br label %case.join.8
case.arm.10.23:
  %t25 = getelementptr ptr, ptr %t0, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 24)
  %t28 = inttoptr i64 7 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 1615808600 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t26, ptr %t33
  %t34 = call ptr @v_dispatch(ptr %t30)
  %t35 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t34, ptr %t35
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 5 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @malloc(i64 8)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t42
  %t43 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t36, ptr %t43
  br label %case.end.10.24
case.end.10.24:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t44 = phi ptr [%t11, %case.end.9.10], [%t27, %case.end.10.24]
  ret ptr %t44
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
