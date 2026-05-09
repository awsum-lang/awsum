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

@.str.0 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"=ok" }
@.str.1 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"=FAIL(expected=" }
@.str.2 = private unnamed_addr constant {i32, i32, [6 x i8]} { i32 6, i32 6, [6 x i8] c", got=" }
@.str.3 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c")" }
@.str.4 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 2, [4 x i8] c"\F0\9F\94\A5" }
@.str.5 = private unnamed_addr constant {i32, i32, [16 x i8]} { i32 16, i32 16, [16 x i8] c"lengthCodePoints" }
@.str.6 = private unnamed_addr constant {i32, i32, [20 x i8]} { i32 20, i32 20, [20 x i8] c"lengthUtf16CodeUnits" }
@.str.7 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"lengthUtf8Bytes" }
@.str.8 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c", " }
@.str.9 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 24)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  ret ptr %buf
}


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  ret ptr %box
}


define internal ptr @__lengthCodePoints(ptr %s) {
entry:
  %total_bytes = load i32, ptr %s
  %total_bytes_64 = zext i32 %total_bytes to i64
  %payload = getelementptr i8, ptr %s, i64 8
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %at_end = icmp uge i64 %i, %total_bytes_64
  br i1 %at_end, label %done, label %body
body:
  %bp = getelementptr i8, ptr %payload, i64 %i
  %b = load i8, ptr %bp
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %inc
inc:
  %n0 = load i32, ptr %n_p
  %n1 = add i32 %n0, 1
  store i32 %n1, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
done:
  %nf = load i32, ptr %n_p
  %box = call ptr @malloc(i64 4)
  store i32 %nf, ptr %box
  ret ptr %box
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
  %u16p = getelementptr i8, ptr %s, i64 4
  %u16 = load i32, ptr %u16p
  %box = call ptr @malloc(i64 4)
  store i32 %u16, ptr %box
  ret ptr %box
}


define internal ptr @__lengthUtf8Bytes(ptr %s) {
  %len32 = load i32, ptr %s
  %box = call ptr @malloc(i64 4)
  store i32 %len32, ptr %box
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

define internal ptr @v_check(ptr %v_expected, ptr %v_actual, ptr %v_label) {
  %t0 = call ptr @__eqUInt32(ptr %v_expected, ptr %v_actual)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 1, label %case.arm.1.6 i64 2, label %case.arm.2.9 ]
case.arm.1.6:
  %t8 = call ptr @__concat(ptr %v_label, ptr @.str.0)
  br label %case.end.1.7
case.end.1.7:
  br label %case.join.5
case.arm.2.9:
  %t11 = call ptr @__concat(ptr %v_label, ptr @.str.1)
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 3, label %case.arm.3.17 i64 4, label %case.arm.4.25 ]
case.arm.3.17:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 16)
  %t22 = inttoptr i64 3 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  br label %case.end.3.18
case.end.3.18:
  br label %case.join.16
case.arm.4.25:
  %t27 = getelementptr ptr, ptr %t11, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @__showUInt32(ptr %v_expected)
  %t30 = call ptr @__concat(ptr %t28, ptr %t29)
  %t31 = getelementptr ptr, ptr %t30, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %case.default.34 [ i64 3, label %case.arm.3.36 i64 4, label %case.arm.4.44 ]
case.arm.3.36:
  %t38 = getelementptr ptr, ptr %t30, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 3 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t39, ptr %t43
  br label %case.end.3.37
case.end.3.37:
  br label %case.join.35
case.arm.4.44:
  %t46 = getelementptr ptr, ptr %t30, i32 1
  %t47 = load ptr, ptr %t46
  %t48 = call ptr @__concat(ptr %t47, ptr @.str.2)
  %t49 = getelementptr ptr, ptr %t48, i32 0
  %t50 = load ptr, ptr %t49
  %t51 = ptrtoint ptr %t50 to i64
  switch i64 %t51, label %case.default.52 [ i64 3, label %case.arm.3.54 i64 4, label %case.arm.4.62 ]
case.arm.3.54:
  %t56 = getelementptr ptr, ptr %t48, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 16)
  %t59 = inttoptr i64 3 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = getelementptr ptr, ptr %t58, i32 1
  store ptr %t57, ptr %t61
  br label %case.end.3.55
case.end.3.55:
  br label %case.join.53
case.arm.4.62:
  %t64 = getelementptr ptr, ptr %t48, i32 1
  %t65 = load ptr, ptr %t64
  %t66 = call ptr @__showUInt32(ptr %v_actual)
  %t67 = call ptr @__concat(ptr %t65, ptr %t66)
  %t68 = getelementptr ptr, ptr %t67, i32 0
  %t69 = load ptr, ptr %t68
  %t70 = ptrtoint ptr %t69 to i64
  switch i64 %t70, label %case.default.71 [ i64 3, label %case.arm.3.73 i64 4, label %case.arm.4.81 ]
case.arm.3.73:
  %t75 = getelementptr ptr, ptr %t67, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = call ptr @malloc(i64 16)
  %t78 = inttoptr i64 3 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t76, ptr %t80
  br label %case.end.3.74
case.end.3.74:
  br label %case.join.72
case.arm.4.81:
  %t83 = getelementptr ptr, ptr %t67, i32 1
  %t84 = load ptr, ptr %t83
  %t85 = call ptr @__concat(ptr %t84, ptr @.str.3)
  br label %case.end.4.82
case.end.4.82:
  br label %case.join.72
case.default.71:
  unreachable
case.join.72:
  %t86 = phi ptr [%t77, %case.end.3.74], [%t85, %case.end.4.82]
  br label %case.end.4.63
case.end.4.63:
  br label %case.join.53
case.default.52:
  unreachable
case.join.53:
  %t87 = phi ptr [%t58, %case.end.3.55], [%t86, %case.end.4.63]
  br label %case.end.4.45
case.end.4.45:
  br label %case.join.35
case.default.34:
  unreachable
case.join.35:
  %t88 = phi ptr [%t40, %case.end.3.37], [%t87, %case.end.4.45]
  br label %case.end.4.26
case.end.4.26:
  br label %case.join.16
case.default.15:
  unreachable
case.join.16:
  %t89 = phi ptr [%t21, %case.end.3.18], [%t88, %case.end.4.26]
  br label %case.end.2.10
case.end.2.10:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t90 = phi ptr [%t8, %case.end.1.7], [%t89, %case.end.2.10]
  ret ptr %t90
}

define internal ptr @v_run() {
  %t0 = call ptr @malloc(i64 4)
  store i32 1, ptr %t0
  %t1 = call ptr @__lengthCodePoints(ptr @.str.4)
  %t2 = call ptr @v_check(ptr %t0, ptr %t1, ptr @.str.5)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.16 ]
case.arm.3.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 3 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.16:
  %t18 = getelementptr ptr, ptr %t2, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 4)
  store i32 2, ptr %t20
  %t21 = call ptr @__lengthUtf16CodeUnits(ptr @.str.4)
  %t22 = call ptr @v_check(ptr %t20, ptr %t21, ptr @.str.6)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 3, label %case.arm.3.28 i64 4, label %case.arm.4.36 ]
case.arm.3.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  br label %case.end.3.29
case.end.3.29:
  br label %case.join.27
case.arm.4.36:
  %t38 = getelementptr ptr, ptr %t22, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @malloc(i64 4)
  store i32 4, ptr %t40
  %t41 = call ptr @__lengthUtf8Bytes(ptr @.str.4)
  %t42 = call ptr @v_check(ptr %t40, ptr %t41, ptr @.str.7)
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 3, label %case.arm.3.48 i64 4, label %case.arm.4.56 ]
case.arm.3.48:
  %t50 = getelementptr ptr, ptr %t42, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @malloc(i64 16)
  %t53 = inttoptr i64 3 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t51, ptr %t55
  br label %case.end.3.49
case.end.3.49:
  br label %case.join.47
case.arm.4.56:
  %t58 = getelementptr ptr, ptr %t42, i32 1
  %t59 = load ptr, ptr %t58
  %t60 = call ptr @__concat(ptr %t19, ptr @.str.8)
  %t61 = getelementptr ptr, ptr %t60, i32 0
  %t62 = load ptr, ptr %t61
  %t63 = ptrtoint ptr %t62 to i64
  switch i64 %t63, label %case.default.64 [ i64 3, label %case.arm.3.66 i64 4, label %case.arm.4.74 ]
case.arm.3.66:
  %t68 = getelementptr ptr, ptr %t60, i32 1
  %t69 = load ptr, ptr %t68
  %t70 = call ptr @malloc(i64 16)
  %t71 = inttoptr i64 3 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t69, ptr %t73
  br label %case.end.3.67
case.end.3.67:
  br label %case.join.65
case.arm.4.74:
  %t76 = getelementptr ptr, ptr %t60, i32 1
  %t77 = load ptr, ptr %t76
  %t78 = call ptr @__concat(ptr %t77, ptr %t39)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 3, label %case.arm.3.84 i64 4, label %case.arm.4.92 ]
case.arm.3.84:
  %t86 = getelementptr ptr, ptr %t78, i32 1
  %t87 = load ptr, ptr %t86
  %t88 = call ptr @malloc(i64 16)
  %t89 = inttoptr i64 3 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  %t91 = getelementptr ptr, ptr %t88, i32 1
  store ptr %t87, ptr %t91
  br label %case.end.3.85
case.end.3.85:
  br label %case.join.83
case.arm.4.92:
  %t94 = getelementptr ptr, ptr %t78, i32 1
  %t95 = load ptr, ptr %t94
  %t96 = call ptr @__concat(ptr %t95, ptr @.str.8)
  %t97 = getelementptr ptr, ptr %t96, i32 0
  %t98 = load ptr, ptr %t97
  %t99 = ptrtoint ptr %t98 to i64
  switch i64 %t99, label %case.default.100 [ i64 3, label %case.arm.3.102 i64 4, label %case.arm.4.110 ]
case.arm.3.102:
  %t104 = getelementptr ptr, ptr %t96, i32 1
  %t105 = load ptr, ptr %t104
  %t106 = call ptr @malloc(i64 16)
  %t107 = inttoptr i64 3 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  %t109 = getelementptr ptr, ptr %t106, i32 1
  store ptr %t105, ptr %t109
  br label %case.end.3.103
case.end.3.103:
  br label %case.join.101
case.arm.4.110:
  %t112 = getelementptr ptr, ptr %t96, i32 1
  %t113 = load ptr, ptr %t112
  %t114 = call ptr @__concat(ptr %t113, ptr %t59)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t115 = phi ptr [%t106, %case.end.3.103], [%t114, %case.end.4.111]
  br label %case.end.4.93
case.end.4.93:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t116 = phi ptr [%t88, %case.end.3.85], [%t115, %case.end.4.93]
  br label %case.end.4.75
case.end.4.75:
  br label %case.join.65
case.default.64:
  unreachable
case.join.65:
  %t117 = phi ptr [%t70, %case.end.3.67], [%t116, %case.end.4.75]
  br label %case.end.4.57
case.end.4.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t118 = phi ptr [%t52, %case.end.3.49], [%t117, %case.end.4.57]
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t119 = phi ptr [%t32, %case.end.3.29], [%t118, %case.end.4.37]
  br label %case.end.4.17
case.end.4.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t120 = phi ptr [%t12, %case.end.3.9], [%t119, %case.end.4.17]
  ret ptr %t120
}

define internal ptr @v_main() {
  %t0 = call ptr @v_run()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.22 ]
case.arm.3.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  %t10 = call ptr @malloc(i64 24)
  %t11 = inttoptr i64 7 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr @.str.9, ptr %t13
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 8)
  %t18 = inttoptr i64 0 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t20
  %t21 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t14, ptr %t21
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.22:
  %t24 = getelementptr ptr, ptr %t0, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = call ptr @malloc(i64 24)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 5 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @malloc(i64 8)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t37
  br label %case.end.4.23
case.end.4.23:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t38 = phi ptr [%t10, %case.end.3.7], [%t26, %case.end.4.23]
  ret ptr %t38
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
