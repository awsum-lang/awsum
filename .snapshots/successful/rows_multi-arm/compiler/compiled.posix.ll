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

define internal ptr @v_whatsInside(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 9, label %case.arm.9.5 i64 10, label %case.arm.10.11 ]
case.arm.9.5:
  %t7 = call ptr @malloc(i64 16)
  %t8 = inttoptr i64 4 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr @.str.1, ptr %t10
  br label %case.end.9.6
case.end.9.6:
  br label %case.join.4
case.arm.10.11:
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
  switch i64 %t26, label %case.default.27 [ i64 1, label %case.arm.1.29 i64 2, label %case.arm.2.35 ]
case.arm.1.29:
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 4 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr @.str.2, ptr %t34
  br label %case.end.1.30
case.end.1.30:
  br label %case.join.28
case.arm.2.35:
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 4 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr @.str.3, ptr %t40
  br label %case.end.2.36
case.end.2.36:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t41 = phi ptr [%t31, %case.end.1.30], [%t37, %case.end.2.36]
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
  br label %case.end.10.12
case.end.10.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t49 = phi ptr [%t7, %case.end.9.6], [%t48, %case.end.10.12]
  ret ptr %t49
}

define internal ptr @v_summary() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v__lift_7(ptr %t0)
  %t8 = call ptr @v_whatsInside(ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 3, label %case.arm.3.14 i64 4, label %case.arm.4.22 ]
case.arm.3.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @malloc(i64 16)
  %t19 = inttoptr i64 3 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t17, ptr %t21
  br label %case.end.3.15
case.end.3.15:
  br label %case.join.13
case.arm.4.22:
  %t24 = getelementptr ptr, ptr %t8, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = call ptr @malloc(i64 16)
  %t27 = inttoptr i64 10 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @malloc(i64 8)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t32
  %t33 = call ptr @v__lift_8(ptr %t26)
  %t34 = call ptr @v_whatsInside(ptr %t33)
  %t35 = getelementptr ptr, ptr %t34, i32 0
  %t36 = load ptr, ptr %t35
  %t37 = ptrtoint ptr %t36 to i64
  switch i64 %t37, label %case.default.38 [ i64 3, label %case.arm.3.40 i64 4, label %case.arm.4.48 ]
case.arm.3.40:
  %t42 = getelementptr ptr, ptr %t34, i32 1
  %t43 = load ptr, ptr %t42
  %t44 = call ptr @malloc(i64 16)
  %t45 = inttoptr i64 3 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t43, ptr %t47
  br label %case.end.3.41
case.end.3.41:
  br label %case.join.39
case.arm.4.48:
  %t50 = getelementptr ptr, ptr %t34, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @malloc(i64 8)
  %t53 = inttoptr i64 9 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = call ptr @v__lift_9(ptr %t52)
  %t56 = call ptr @v_whatsInside(ptr %t55)
  %t57 = getelementptr ptr, ptr %t56, i32 0
  %t58 = load ptr, ptr %t57
  %t59 = ptrtoint ptr %t58 to i64
  switch i64 %t59, label %case.default.60 [ i64 3, label %case.arm.3.62 i64 4, label %case.arm.4.70 ]
case.arm.3.62:
  %t64 = getelementptr ptr, ptr %t56, i32 1
  %t65 = load ptr, ptr %t64
  %t66 = call ptr @malloc(i64 16)
  %t67 = inttoptr i64 3 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t65, ptr %t69
  br label %case.end.3.63
case.end.3.63:
  br label %case.join.61
case.arm.4.70:
  %t72 = getelementptr ptr, ptr %t56, i32 1
  %t73 = load ptr, ptr %t72
  %t74 = call ptr @__concat(ptr %t25, ptr @.str.5)
  %t75 = getelementptr ptr, ptr %t74, i32 0
  %t76 = load ptr, ptr %t75
  %t77 = ptrtoint ptr %t76 to i64
  switch i64 %t77, label %case.default.78 [ i64 3, label %case.arm.3.80 i64 4, label %case.arm.4.88 ]
case.arm.3.80:
  %t82 = getelementptr ptr, ptr %t74, i32 1
  %t83 = load ptr, ptr %t82
  %t84 = call ptr @malloc(i64 16)
  %t85 = inttoptr i64 3 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t83, ptr %t87
  br label %case.end.3.81
case.end.3.81:
  br label %case.join.79
case.arm.4.88:
  %t90 = getelementptr ptr, ptr %t74, i32 1
  %t91 = load ptr, ptr %t90
  %t92 = call ptr @__concat(ptr %t91, ptr %t51)
  %t93 = getelementptr ptr, ptr %t92, i32 0
  %t94 = load ptr, ptr %t93
  %t95 = ptrtoint ptr %t94 to i64
  switch i64 %t95, label %case.default.96 [ i64 3, label %case.arm.3.98 i64 4, label %case.arm.4.106 ]
case.arm.3.98:
  %t100 = getelementptr ptr, ptr %t92, i32 1
  %t101 = load ptr, ptr %t100
  %t102 = call ptr @malloc(i64 16)
  %t103 = inttoptr i64 3 to ptr
  %t104 = getelementptr ptr, ptr %t102, i32 0
  store ptr %t103, ptr %t104
  %t105 = getelementptr ptr, ptr %t102, i32 1
  store ptr %t101, ptr %t105
  br label %case.end.3.99
case.end.3.99:
  br label %case.join.97
case.arm.4.106:
  %t108 = getelementptr ptr, ptr %t92, i32 1
  %t109 = load ptr, ptr %t108
  %t110 = call ptr @__concat(ptr %t109, ptr @.str.5)
  %t111 = getelementptr ptr, ptr %t110, i32 0
  %t112 = load ptr, ptr %t111
  %t113 = ptrtoint ptr %t112 to i64
  switch i64 %t113, label %case.default.114 [ i64 3, label %case.arm.3.116 i64 4, label %case.arm.4.124 ]
case.arm.3.116:
  %t118 = getelementptr ptr, ptr %t110, i32 1
  %t119 = load ptr, ptr %t118
  %t120 = call ptr @malloc(i64 16)
  %t121 = inttoptr i64 3 to ptr
  %t122 = getelementptr ptr, ptr %t120, i32 0
  store ptr %t121, ptr %t122
  %t123 = getelementptr ptr, ptr %t120, i32 1
  store ptr %t119, ptr %t123
  br label %case.end.3.117
case.end.3.117:
  br label %case.join.115
case.arm.4.124:
  %t126 = getelementptr ptr, ptr %t110, i32 1
  %t127 = load ptr, ptr %t126
  %t128 = call ptr @__concat(ptr %t127, ptr %t73)
  br label %case.end.4.125
case.end.4.125:
  br label %case.join.115
case.default.114:
  unreachable
case.join.115:
  %t129 = phi ptr [%t120, %case.end.3.117], [%t128, %case.end.4.125]
  br label %case.end.4.107
case.end.4.107:
  br label %case.join.97
case.default.96:
  unreachable
case.join.97:
  %t130 = phi ptr [%t102, %case.end.3.99], [%t129, %case.end.4.107]
  br label %case.end.4.89
case.end.4.89:
  br label %case.join.79
case.default.78:
  unreachable
case.join.79:
  %t131 = phi ptr [%t84, %case.end.3.81], [%t130, %case.end.4.89]
  br label %case.end.4.71
case.end.4.71:
  br label %case.join.61
case.default.60:
  unreachable
case.join.61:
  %t132 = phi ptr [%t66, %case.end.3.63], [%t131, %case.end.4.71]
  br label %case.end.4.49
case.end.4.49:
  br label %case.join.39
case.default.38:
  unreachable
case.join.39:
  %t133 = phi ptr [%t44, %case.end.3.41], [%t132, %case.end.4.49]
  br label %case.end.4.23
case.end.4.23:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t134 = phi ptr [%t18, %case.end.3.15], [%t133, %case.end.4.23]
  ret ptr %t134
}

define internal ptr @v_main() {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @v__let_10(ptr %t0)
  ret ptr %t1
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

define internal ptr @v__lift_8(ptr %v___input) {
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
  %t18 = inttoptr i64 1759602215 to ptr
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

define internal ptr @v__lift_9(ptr %v___input) {
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
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  br label %case.end.10.11
case.end.10.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t18 = phi ptr [%t7, %case.end.9.6], [%t14, %case.end.10.11]
  ret ptr %t18
}

define internal ptr @v__let_10(ptr %v_res) {
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
  store ptr @.str.6, ptr %t12
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
