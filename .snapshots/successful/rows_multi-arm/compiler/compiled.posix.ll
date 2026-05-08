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

@.str.0 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 4, [4 x i8] c"Unit" }
@.str.1 = private unnamed_addr constant {i32, i32, [7 x i8]} { i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.2 = private unnamed_addr constant {i32, i32, [9 x i8]} { i32 9, i32 9, [9 x i8] c"Just True" }
@.str.3 = private unnamed_addr constant {i32, i32, [10 x i8]} { i32 10, i32 10, [10 x i8] c"Just False" }
@.str.4 = private unnamed_addr constant {i32, i32, [5 x i8]} { i32 5, i32 5, [5 x i8] c"Just " }
@.str.5 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c"; " }
@.str.6 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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
  %stl_tag = inttoptr i64 0 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
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
  %right_tag = inttoptr i64 1 to ptr
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


define internal ptr @v_showUnit(ptr %v__wild0) {
  ret ptr @.str.0
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
  switch i64 %t7, label %tco.case.default.8 [ i64 0, label %tco.case.arm.0.9 i64 2, label %tco.case.arm.2.12 ]
tco.case.arm.0.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.12:
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

define internal ptr @v_whatsInside(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 16)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr @.str.1, ptr %t10
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_x, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t14, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %case.default.18 [ i64 796142685, label %case.arm.796142685.20 i64 1759602215, label %case.arm.1759602215.42 ]
case.arm.796142685.20:
  %t22 = getelementptr ptr, ptr %t14, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 0, label %case.arm.0.29 i64 1, label %case.arm.1.35 ]
case.arm.0.29:
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 1 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr @.str.2, ptr %t34
  br label %case.end.0.30
case.end.0.30:
  br label %case.join.28
case.arm.1.35:
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 1 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr @.str.3, ptr %t40
  br label %case.end.1.36
case.end.1.36:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t41 = phi ptr [%t31, %case.end.0.30], [%t37, %case.end.1.36]
  br label %case.end.796142685.21
case.end.796142685.21:
  br label %case.join.19
case.arm.1759602215.42:
  %t44 = getelementptr ptr, ptr %t14, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @v_showUnit(ptr %t45)
  %t47 = call ptr @__concat(ptr @.str.4, ptr %t46)
  br label %case.end.1759602215.43
case.end.1759602215.43:
  br label %case.join.19
case.default.18:
  unreachable
case.join.19:
  %t48 = phi ptr [%t41, %case.end.796142685.21], [%t47, %case.end.1759602215.43]
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t49 = phi ptr [%t7, %case.end.0.6], [%t48, %case.end.1.12]
  ret ptr %t49
}

define internal ptr @v_summary() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 796142685 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 0 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t10
  %t11 = call ptr @v_whatsInside(ptr %t0)
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 0, label %case.arm.0.17 i64 1, label %case.arm.1.25 ]
case.arm.0.17:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 16)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  br label %case.end.0.18
case.end.0.18:
  br label %case.join.16
case.arm.1.25:
  %t27 = getelementptr ptr, ptr %t11, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 1 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 1759602215 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @malloc(i64 8)
  %t36 = inttoptr i64 0 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t38
  %t39 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t39
  %t40 = call ptr @v_whatsInside(ptr %t29)
  %t41 = getelementptr ptr, ptr %t40, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %case.default.44 [ i64 0, label %case.arm.0.46 i64 1, label %case.arm.1.54 ]
case.arm.0.46:
  %t48 = getelementptr ptr, ptr %t40, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = call ptr @malloc(i64 16)
  %t51 = inttoptr i64 0 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t49, ptr %t53
  br label %case.end.0.47
case.end.0.47:
  br label %case.join.45
case.arm.1.54:
  %t56 = getelementptr ptr, ptr %t40, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 8)
  %t59 = inttoptr i64 0 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = call ptr @v_whatsInside(ptr %t58)
  %t62 = getelementptr ptr, ptr %t61, i32 0
  %t63 = load ptr, ptr %t62
  %t64 = ptrtoint ptr %t63 to i64
  switch i64 %t64, label %case.default.65 [ i64 0, label %case.arm.0.67 i64 1, label %case.arm.1.75 ]
case.arm.0.67:
  %t69 = getelementptr ptr, ptr %t61, i32 1
  %t70 = load ptr, ptr %t69
  %t71 = call ptr @malloc(i64 16)
  %t72 = inttoptr i64 0 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t70, ptr %t74
  br label %case.end.0.68
case.end.0.68:
  br label %case.join.66
case.arm.1.75:
  %t77 = getelementptr ptr, ptr %t61, i32 1
  %t78 = load ptr, ptr %t77
  %t79 = call ptr @__concat(ptr %t28, ptr @.str.5)
  %t80 = getelementptr ptr, ptr %t79, i32 0
  %t81 = load ptr, ptr %t80
  %t82 = ptrtoint ptr %t81 to i64
  switch i64 %t82, label %case.default.83 [ i64 0, label %case.arm.0.85 i64 1, label %case.arm.1.93 ]
case.arm.0.85:
  %t87 = getelementptr ptr, ptr %t79, i32 1
  %t88 = load ptr, ptr %t87
  %t89 = call ptr @malloc(i64 16)
  %t90 = inttoptr i64 0 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  %t92 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t88, ptr %t92
  br label %case.end.0.86
case.end.0.86:
  br label %case.join.84
case.arm.1.93:
  %t95 = getelementptr ptr, ptr %t79, i32 1
  %t96 = load ptr, ptr %t95
  %t97 = call ptr @__concat(ptr %t96, ptr %t57)
  %t98 = getelementptr ptr, ptr %t97, i32 0
  %t99 = load ptr, ptr %t98
  %t100 = ptrtoint ptr %t99 to i64
  switch i64 %t100, label %case.default.101 [ i64 0, label %case.arm.0.103 i64 1, label %case.arm.1.111 ]
case.arm.0.103:
  %t105 = getelementptr ptr, ptr %t97, i32 1
  %t106 = load ptr, ptr %t105
  %t107 = call ptr @malloc(i64 16)
  %t108 = inttoptr i64 0 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t106, ptr %t110
  br label %case.end.0.104
case.end.0.104:
  br label %case.join.102
case.arm.1.111:
  %t113 = getelementptr ptr, ptr %t97, i32 1
  %t114 = load ptr, ptr %t113
  %t115 = call ptr @__concat(ptr %t114, ptr @.str.5)
  %t116 = getelementptr ptr, ptr %t115, i32 0
  %t117 = load ptr, ptr %t116
  %t118 = ptrtoint ptr %t117 to i64
  switch i64 %t118, label %case.default.119 [ i64 0, label %case.arm.0.121 i64 1, label %case.arm.1.129 ]
case.arm.0.121:
  %t123 = getelementptr ptr, ptr %t115, i32 1
  %t124 = load ptr, ptr %t123
  %t125 = call ptr @malloc(i64 16)
  %t126 = inttoptr i64 0 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t124, ptr %t128
  br label %case.end.0.122
case.end.0.122:
  br label %case.join.120
case.arm.1.129:
  %t131 = getelementptr ptr, ptr %t115, i32 1
  %t132 = load ptr, ptr %t131
  %t133 = call ptr @__concat(ptr %t132, ptr %t78)
  br label %case.end.1.130
case.end.1.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t134 = phi ptr [%t125, %case.end.0.122], [%t133, %case.end.1.130]
  br label %case.end.1.112
case.end.1.112:
  br label %case.join.102
case.default.101:
  unreachable
case.join.102:
  %t135 = phi ptr [%t107, %case.end.0.104], [%t134, %case.end.1.112]
  br label %case.end.1.94
case.end.1.94:
  br label %case.join.84
case.default.83:
  unreachable
case.join.84:
  %t136 = phi ptr [%t89, %case.end.0.86], [%t135, %case.end.1.94]
  br label %case.end.1.76
case.end.1.76:
  br label %case.join.66
case.default.65:
  unreachable
case.join.66:
  %t137 = phi ptr [%t71, %case.end.0.68], [%t136, %case.end.1.76]
  br label %case.end.1.55
case.end.1.55:
  br label %case.join.45
case.default.44:
  unreachable
case.join.45:
  %t138 = phi ptr [%t50, %case.end.0.47], [%t137, %case.end.1.55]
  br label %case.end.1.26
case.end.1.26:
  br label %case.join.16
case.default.15:
  unreachable
case.join.16:
  %t139 = phi ptr [%t21, %case.end.0.18], [%t138, %case.end.1.26]
  ret ptr %t139
}

define internal ptr @v_main() {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @v__let_7(ptr %t0)
  ret ptr %t1
}

define internal ptr @v__let_7(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.21 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 24)
  %t10 = inttoptr i64 2 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr @.str.6, ptr %t12
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 0 to ptr
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
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.21:
  %t23 = getelementptr ptr, ptr %v_res, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @malloc(i64 24)
  %t26 = inttoptr i64 2 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t24, ptr %t28
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 0 to ptr
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
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t37 = phi ptr [%t9, %case.end.0.6], [%t25, %case.end.1.22]
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
