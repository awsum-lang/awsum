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

@.str.0 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"1" }
@.str.1 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"," }
@.str.2 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"2" }
@.str.3 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"3" }
@.str.4 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"4" }
@.str.5 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"5" }
@.str.6 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"6" }
@.str.7 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"7" }
@.str.8 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"8" }
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

define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 19, label %case.arm.19.5 i64 20, label %case.arm.20.51 ]
case.arm.19.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 19, label %case.arm.19.14 i64 20, label %case.arm.20.32 ]
case.arm.19.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 19, label %case.arm.19.23 i64 20, label %case.arm.20.27 ]
case.arm.19.23:
  %t25 = getelementptr ptr, ptr %t17, i32 1
  %t26 = load ptr, ptr %t25
  br label %case.end.19.24
case.end.19.24:
  br label %case.join.22
case.arm.20.27:
  %t29 = getelementptr ptr, ptr %t17, i32 1
  %t30 = load ptr, ptr %t29
  br label %case.end.20.28
case.end.20.28:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t31 = phi ptr [%t26, %case.end.19.24], [%t30, %case.end.20.28]
  br label %case.end.19.15
case.end.19.15:
  br label %case.join.13
case.arm.20.32:
  %t34 = getelementptr ptr, ptr %t8, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = getelementptr ptr, ptr %t35, i32 0
  %t37 = load ptr, ptr %t36
  %t38 = ptrtoint ptr %t37 to i64
  switch i64 %t38, label %case.default.39 [ i64 19, label %case.arm.19.41 i64 20, label %case.arm.20.45 ]
case.arm.19.41:
  %t43 = getelementptr ptr, ptr %t35, i32 1
  %t44 = load ptr, ptr %t43
  br label %case.end.19.42
case.end.19.42:
  br label %case.join.40
case.arm.20.45:
  %t47 = getelementptr ptr, ptr %t35, i32 1
  %t48 = load ptr, ptr %t47
  br label %case.end.20.46
case.end.20.46:
  br label %case.join.40
case.default.39:
  unreachable
case.join.40:
  %t49 = phi ptr [%t44, %case.end.19.42], [%t48, %case.end.20.46]
  br label %case.end.20.33
case.end.20.33:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t50 = phi ptr [%t31, %case.end.19.15], [%t49, %case.end.20.33]
  br label %case.end.19.6
case.end.19.6:
  br label %case.join.4
case.arm.20.51:
  %t53 = getelementptr ptr, ptr %v_r, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 19, label %case.arm.19.60 i64 20, label %case.arm.20.78 ]
case.arm.19.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = getelementptr ptr, ptr %t63, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 19, label %case.arm.19.69 i64 20, label %case.arm.20.73 ]
case.arm.19.69:
  %t71 = getelementptr ptr, ptr %t63, i32 1
  %t72 = load ptr, ptr %t71
  br label %case.end.19.70
case.end.19.70:
  br label %case.join.68
case.arm.20.73:
  %t75 = getelementptr ptr, ptr %t63, i32 1
  %t76 = load ptr, ptr %t75
  br label %case.end.20.74
case.end.20.74:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t77 = phi ptr [%t72, %case.end.19.70], [%t76, %case.end.20.74]
  br label %case.end.19.61
case.end.19.61:
  br label %case.join.59
case.arm.20.78:
  %t80 = getelementptr ptr, ptr %t54, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t81, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 19, label %case.arm.19.87 i64 20, label %case.arm.20.91 ]
case.arm.19.87:
  %t89 = getelementptr ptr, ptr %t81, i32 1
  %t90 = load ptr, ptr %t89
  br label %case.end.19.88
case.end.19.88:
  br label %case.join.86
case.arm.20.91:
  %t93 = getelementptr ptr, ptr %t81, i32 1
  %t94 = load ptr, ptr %t93
  br label %case.end.20.92
case.end.20.92:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t95 = phi ptr [%t90, %case.end.19.88], [%t94, %case.end.20.92]
  br label %case.end.20.79
case.end.20.79:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t96 = phi ptr [%t77, %case.end.19.61], [%t95, %case.end.20.79]
  br label %case.end.20.52
case.end.20.52:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t97 = phi ptr [%t50, %case.end.19.6], [%t96, %case.end.20.52]
  ret ptr %t97
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 19 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 19 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 16)
  %t7 = inttoptr i64 19 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t6, i32 1
  store ptr @.str.0, ptr %t9
  %t10 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t11
  %t12 = call ptr @v_unwrap(ptr %t0)
  %t13 = call ptr @__concat(ptr %t12, ptr @.str.1)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 3, label %case.arm.3.19 i64 4, label %case.arm.4.27 ]
case.arm.3.19:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  br label %case.end.3.20
case.end.3.20:
  br label %case.join.18
case.arm.4.27:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 19 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @malloc(i64 16)
  %t35 = inttoptr i64 19 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 20 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr @.str.2, ptr %t40
  %t41 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t41
  %t42 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t42
  %t43 = call ptr @v_unwrap(ptr %t31)
  %t44 = call ptr @__concat(ptr %t30, ptr %t43)
  %t45 = getelementptr ptr, ptr %t44, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 3, label %case.arm.3.50 i64 4, label %case.arm.4.58 ]
case.arm.3.50:
  %t52 = getelementptr ptr, ptr %t44, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = call ptr @malloc(i64 16)
  %t55 = inttoptr i64 3 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t53, ptr %t57
  br label %case.end.3.51
case.end.3.51:
  br label %case.join.49
case.arm.4.58:
  %t60 = getelementptr ptr, ptr %t44, i32 1
  %t61 = load ptr, ptr %t60
  %t62 = call ptr @__concat(ptr %t61, ptr @.str.1)
  %t63 = getelementptr ptr, ptr %t62, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 3, label %case.arm.3.68 i64 4, label %case.arm.4.76 ]
case.arm.3.68:
  %t70 = getelementptr ptr, ptr %t62, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 3 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  br label %case.end.3.69
case.end.3.69:
  br label %case.join.67
case.arm.4.76:
  %t78 = getelementptr ptr, ptr %t62, i32 1
  %t79 = load ptr, ptr %t78
  %t80 = call ptr @malloc(i64 16)
  %t81 = inttoptr i64 19 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = call ptr @malloc(i64 16)
  %t84 = inttoptr i64 20 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  %t86 = call ptr @malloc(i64 16)
  %t87 = inttoptr i64 19 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  %t89 = getelementptr ptr, ptr %t86, i32 1
  store ptr @.str.3, ptr %t89
  %t90 = getelementptr ptr, ptr %t83, i32 1
  store ptr %t86, ptr %t90
  %t91 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t83, ptr %t91
  %t92 = call ptr @v_unwrap(ptr %t80)
  %t93 = call ptr @__concat(ptr %t79, ptr %t92)
  %t94 = getelementptr ptr, ptr %t93, i32 0
  %t95 = load ptr, ptr %t94
  %t96 = ptrtoint ptr %t95 to i64
  switch i64 %t96, label %case.default.97 [ i64 3, label %case.arm.3.99 i64 4, label %case.arm.4.107 ]
case.arm.3.99:
  %t101 = getelementptr ptr, ptr %t93, i32 1
  %t102 = load ptr, ptr %t101
  %t103 = call ptr @malloc(i64 16)
  %t104 = inttoptr i64 3 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  %t106 = getelementptr ptr, ptr %t103, i32 1
  store ptr %t102, ptr %t106
  br label %case.end.3.100
case.end.3.100:
  br label %case.join.98
case.arm.4.107:
  %t109 = getelementptr ptr, ptr %t93, i32 1
  %t110 = load ptr, ptr %t109
  %t111 = call ptr @__concat(ptr %t110, ptr @.str.1)
  %t112 = getelementptr ptr, ptr %t111, i32 0
  %t113 = load ptr, ptr %t112
  %t114 = ptrtoint ptr %t113 to i64
  switch i64 %t114, label %case.default.115 [ i64 3, label %case.arm.3.117 i64 4, label %case.arm.4.125 ]
case.arm.3.117:
  %t119 = getelementptr ptr, ptr %t111, i32 1
  %t120 = load ptr, ptr %t119
  %t121 = call ptr @malloc(i64 16)
  %t122 = inttoptr i64 3 to ptr
  %t123 = getelementptr ptr, ptr %t121, i32 0
  store ptr %t122, ptr %t123
  %t124 = getelementptr ptr, ptr %t121, i32 1
  store ptr %t120, ptr %t124
  br label %case.end.3.118
case.end.3.118:
  br label %case.join.116
case.arm.4.125:
  %t127 = getelementptr ptr, ptr %t111, i32 1
  %t128 = load ptr, ptr %t127
  %t129 = call ptr @malloc(i64 16)
  %t130 = inttoptr i64 19 to ptr
  %t131 = getelementptr ptr, ptr %t129, i32 0
  store ptr %t130, ptr %t131
  %t132 = call ptr @malloc(i64 16)
  %t133 = inttoptr i64 20 to ptr
  %t134 = getelementptr ptr, ptr %t132, i32 0
  store ptr %t133, ptr %t134
  %t135 = call ptr @malloc(i64 16)
  %t136 = inttoptr i64 20 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = getelementptr ptr, ptr %t135, i32 1
  store ptr @.str.4, ptr %t138
  %t139 = getelementptr ptr, ptr %t132, i32 1
  store ptr %t135, ptr %t139
  %t140 = getelementptr ptr, ptr %t129, i32 1
  store ptr %t132, ptr %t140
  %t141 = call ptr @v_unwrap(ptr %t129)
  %t142 = call ptr @__concat(ptr %t128, ptr %t141)
  %t143 = getelementptr ptr, ptr %t142, i32 0
  %t144 = load ptr, ptr %t143
  %t145 = ptrtoint ptr %t144 to i64
  switch i64 %t145, label %case.default.146 [ i64 3, label %case.arm.3.148 i64 4, label %case.arm.4.156 ]
case.arm.3.148:
  %t150 = getelementptr ptr, ptr %t142, i32 1
  %t151 = load ptr, ptr %t150
  %t152 = call ptr @malloc(i64 16)
  %t153 = inttoptr i64 3 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  %t155 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t151, ptr %t155
  br label %case.end.3.149
case.end.3.149:
  br label %case.join.147
case.arm.4.156:
  %t158 = getelementptr ptr, ptr %t142, i32 1
  %t159 = load ptr, ptr %t158
  %t160 = call ptr @__concat(ptr %t159, ptr @.str.1)
  %t161 = getelementptr ptr, ptr %t160, i32 0
  %t162 = load ptr, ptr %t161
  %t163 = ptrtoint ptr %t162 to i64
  switch i64 %t163, label %case.default.164 [ i64 3, label %case.arm.3.166 i64 4, label %case.arm.4.174 ]
case.arm.3.166:
  %t168 = getelementptr ptr, ptr %t160, i32 1
  %t169 = load ptr, ptr %t168
  %t170 = call ptr @malloc(i64 16)
  %t171 = inttoptr i64 3 to ptr
  %t172 = getelementptr ptr, ptr %t170, i32 0
  store ptr %t171, ptr %t172
  %t173 = getelementptr ptr, ptr %t170, i32 1
  store ptr %t169, ptr %t173
  br label %case.end.3.167
case.end.3.167:
  br label %case.join.165
case.arm.4.174:
  %t176 = getelementptr ptr, ptr %t160, i32 1
  %t177 = load ptr, ptr %t176
  %t178 = call ptr @malloc(i64 16)
  %t179 = inttoptr i64 20 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  %t181 = call ptr @malloc(i64 16)
  %t182 = inttoptr i64 19 to ptr
  %t183 = getelementptr ptr, ptr %t181, i32 0
  store ptr %t182, ptr %t183
  %t184 = call ptr @malloc(i64 16)
  %t185 = inttoptr i64 19 to ptr
  %t186 = getelementptr ptr, ptr %t184, i32 0
  store ptr %t185, ptr %t186
  %t187 = getelementptr ptr, ptr %t184, i32 1
  store ptr @.str.5, ptr %t187
  %t188 = getelementptr ptr, ptr %t181, i32 1
  store ptr %t184, ptr %t188
  %t189 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t181, ptr %t189
  %t190 = call ptr @v_unwrap(ptr %t178)
  %t191 = call ptr @__concat(ptr %t177, ptr %t190)
  %t192 = getelementptr ptr, ptr %t191, i32 0
  %t193 = load ptr, ptr %t192
  %t194 = ptrtoint ptr %t193 to i64
  switch i64 %t194, label %case.default.195 [ i64 3, label %case.arm.3.197 i64 4, label %case.arm.4.205 ]
case.arm.3.197:
  %t199 = getelementptr ptr, ptr %t191, i32 1
  %t200 = load ptr, ptr %t199
  %t201 = call ptr @malloc(i64 16)
  %t202 = inttoptr i64 3 to ptr
  %t203 = getelementptr ptr, ptr %t201, i32 0
  store ptr %t202, ptr %t203
  %t204 = getelementptr ptr, ptr %t201, i32 1
  store ptr %t200, ptr %t204
  br label %case.end.3.198
case.end.3.198:
  br label %case.join.196
case.arm.4.205:
  %t207 = getelementptr ptr, ptr %t191, i32 1
  %t208 = load ptr, ptr %t207
  %t209 = call ptr @__concat(ptr %t208, ptr @.str.1)
  %t210 = getelementptr ptr, ptr %t209, i32 0
  %t211 = load ptr, ptr %t210
  %t212 = ptrtoint ptr %t211 to i64
  switch i64 %t212, label %case.default.213 [ i64 3, label %case.arm.3.215 i64 4, label %case.arm.4.223 ]
case.arm.3.215:
  %t217 = getelementptr ptr, ptr %t209, i32 1
  %t218 = load ptr, ptr %t217
  %t219 = call ptr @malloc(i64 16)
  %t220 = inttoptr i64 3 to ptr
  %t221 = getelementptr ptr, ptr %t219, i32 0
  store ptr %t220, ptr %t221
  %t222 = getelementptr ptr, ptr %t219, i32 1
  store ptr %t218, ptr %t222
  br label %case.end.3.216
case.end.3.216:
  br label %case.join.214
case.arm.4.223:
  %t225 = getelementptr ptr, ptr %t209, i32 1
  %t226 = load ptr, ptr %t225
  %t227 = call ptr @malloc(i64 16)
  %t228 = inttoptr i64 20 to ptr
  %t229 = getelementptr ptr, ptr %t227, i32 0
  store ptr %t228, ptr %t229
  %t230 = call ptr @malloc(i64 16)
  %t231 = inttoptr i64 19 to ptr
  %t232 = getelementptr ptr, ptr %t230, i32 0
  store ptr %t231, ptr %t232
  %t233 = call ptr @malloc(i64 16)
  %t234 = inttoptr i64 20 to ptr
  %t235 = getelementptr ptr, ptr %t233, i32 0
  store ptr %t234, ptr %t235
  %t236 = getelementptr ptr, ptr %t233, i32 1
  store ptr @.str.6, ptr %t236
  %t237 = getelementptr ptr, ptr %t230, i32 1
  store ptr %t233, ptr %t237
  %t238 = getelementptr ptr, ptr %t227, i32 1
  store ptr %t230, ptr %t238
  %t239 = call ptr @v_unwrap(ptr %t227)
  %t240 = call ptr @__concat(ptr %t226, ptr %t239)
  %t241 = getelementptr ptr, ptr %t240, i32 0
  %t242 = load ptr, ptr %t241
  %t243 = ptrtoint ptr %t242 to i64
  switch i64 %t243, label %case.default.244 [ i64 3, label %case.arm.3.246 i64 4, label %case.arm.4.254 ]
case.arm.3.246:
  %t248 = getelementptr ptr, ptr %t240, i32 1
  %t249 = load ptr, ptr %t248
  %t250 = call ptr @malloc(i64 16)
  %t251 = inttoptr i64 3 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  %t253 = getelementptr ptr, ptr %t250, i32 1
  store ptr %t249, ptr %t253
  br label %case.end.3.247
case.end.3.247:
  br label %case.join.245
case.arm.4.254:
  %t256 = getelementptr ptr, ptr %t240, i32 1
  %t257 = load ptr, ptr %t256
  %t258 = call ptr @__concat(ptr %t257, ptr @.str.1)
  %t259 = getelementptr ptr, ptr %t258, i32 0
  %t260 = load ptr, ptr %t259
  %t261 = ptrtoint ptr %t260 to i64
  switch i64 %t261, label %case.default.262 [ i64 3, label %case.arm.3.264 i64 4, label %case.arm.4.272 ]
case.arm.3.264:
  %t266 = getelementptr ptr, ptr %t258, i32 1
  %t267 = load ptr, ptr %t266
  %t268 = call ptr @malloc(i64 16)
  %t269 = inttoptr i64 3 to ptr
  %t270 = getelementptr ptr, ptr %t268, i32 0
  store ptr %t269, ptr %t270
  %t271 = getelementptr ptr, ptr %t268, i32 1
  store ptr %t267, ptr %t271
  br label %case.end.3.265
case.end.3.265:
  br label %case.join.263
case.arm.4.272:
  %t274 = getelementptr ptr, ptr %t258, i32 1
  %t275 = load ptr, ptr %t274
  %t276 = call ptr @malloc(i64 16)
  %t277 = inttoptr i64 20 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  %t279 = call ptr @malloc(i64 16)
  %t280 = inttoptr i64 20 to ptr
  %t281 = getelementptr ptr, ptr %t279, i32 0
  store ptr %t280, ptr %t281
  %t282 = call ptr @malloc(i64 16)
  %t283 = inttoptr i64 19 to ptr
  %t284 = getelementptr ptr, ptr %t282, i32 0
  store ptr %t283, ptr %t284
  %t285 = getelementptr ptr, ptr %t282, i32 1
  store ptr @.str.7, ptr %t285
  %t286 = getelementptr ptr, ptr %t279, i32 1
  store ptr %t282, ptr %t286
  %t287 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t279, ptr %t287
  %t288 = call ptr @v_unwrap(ptr %t276)
  %t289 = call ptr @__concat(ptr %t275, ptr %t288)
  %t290 = getelementptr ptr, ptr %t289, i32 0
  %t291 = load ptr, ptr %t290
  %t292 = ptrtoint ptr %t291 to i64
  switch i64 %t292, label %case.default.293 [ i64 3, label %case.arm.3.295 i64 4, label %case.arm.4.303 ]
case.arm.3.295:
  %t297 = getelementptr ptr, ptr %t289, i32 1
  %t298 = load ptr, ptr %t297
  %t299 = call ptr @malloc(i64 16)
  %t300 = inttoptr i64 3 to ptr
  %t301 = getelementptr ptr, ptr %t299, i32 0
  store ptr %t300, ptr %t301
  %t302 = getelementptr ptr, ptr %t299, i32 1
  store ptr %t298, ptr %t302
  br label %case.end.3.296
case.end.3.296:
  br label %case.join.294
case.arm.4.303:
  %t305 = getelementptr ptr, ptr %t289, i32 1
  %t306 = load ptr, ptr %t305
  %t307 = call ptr @__concat(ptr %t306, ptr @.str.1)
  %t308 = getelementptr ptr, ptr %t307, i32 0
  %t309 = load ptr, ptr %t308
  %t310 = ptrtoint ptr %t309 to i64
  switch i64 %t310, label %case.default.311 [ i64 3, label %case.arm.3.313 i64 4, label %case.arm.4.321 ]
case.arm.3.313:
  %t315 = getelementptr ptr, ptr %t307, i32 1
  %t316 = load ptr, ptr %t315
  %t317 = call ptr @malloc(i64 16)
  %t318 = inttoptr i64 3 to ptr
  %t319 = getelementptr ptr, ptr %t317, i32 0
  store ptr %t318, ptr %t319
  %t320 = getelementptr ptr, ptr %t317, i32 1
  store ptr %t316, ptr %t320
  br label %case.end.3.314
case.end.3.314:
  br label %case.join.312
case.arm.4.321:
  %t323 = getelementptr ptr, ptr %t307, i32 1
  %t324 = load ptr, ptr %t323
  %t325 = call ptr @malloc(i64 16)
  %t326 = inttoptr i64 20 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  %t328 = call ptr @malloc(i64 16)
  %t329 = inttoptr i64 20 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  %t331 = call ptr @malloc(i64 16)
  %t332 = inttoptr i64 20 to ptr
  %t333 = getelementptr ptr, ptr %t331, i32 0
  store ptr %t332, ptr %t333
  %t334 = getelementptr ptr, ptr %t331, i32 1
  store ptr @.str.8, ptr %t334
  %t335 = getelementptr ptr, ptr %t328, i32 1
  store ptr %t331, ptr %t335
  %t336 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t328, ptr %t336
  %t337 = call ptr @v_unwrap(ptr %t325)
  %t338 = call ptr @__concat(ptr %t324, ptr %t337)
  br label %case.end.4.322
case.end.4.322:
  br label %case.join.312
case.default.311:
  unreachable
case.join.312:
  %t339 = phi ptr [%t317, %case.end.3.314], [%t338, %case.end.4.322]
  br label %case.end.4.304
case.end.4.304:
  br label %case.join.294
case.default.293:
  unreachable
case.join.294:
  %t340 = phi ptr [%t299, %case.end.3.296], [%t339, %case.end.4.304]
  br label %case.end.4.273
case.end.4.273:
  br label %case.join.263
case.default.262:
  unreachable
case.join.263:
  %t341 = phi ptr [%t268, %case.end.3.265], [%t340, %case.end.4.273]
  br label %case.end.4.255
case.end.4.255:
  br label %case.join.245
case.default.244:
  unreachable
case.join.245:
  %t342 = phi ptr [%t250, %case.end.3.247], [%t341, %case.end.4.255]
  br label %case.end.4.224
case.end.4.224:
  br label %case.join.214
case.default.213:
  unreachable
case.join.214:
  %t343 = phi ptr [%t219, %case.end.3.216], [%t342, %case.end.4.224]
  br label %case.end.4.206
case.end.4.206:
  br label %case.join.196
case.default.195:
  unreachable
case.join.196:
  %t344 = phi ptr [%t201, %case.end.3.198], [%t343, %case.end.4.206]
  br label %case.end.4.175
case.end.4.175:
  br label %case.join.165
case.default.164:
  unreachable
case.join.165:
  %t345 = phi ptr [%t170, %case.end.3.167], [%t344, %case.end.4.175]
  br label %case.end.4.157
case.end.4.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t346 = phi ptr [%t152, %case.end.3.149], [%t345, %case.end.4.157]
  br label %case.end.4.126
case.end.4.126:
  br label %case.join.116
case.default.115:
  unreachable
case.join.116:
  %t347 = phi ptr [%t121, %case.end.3.118], [%t346, %case.end.4.126]
  br label %case.end.4.108
case.end.4.108:
  br label %case.join.98
case.default.97:
  unreachable
case.join.98:
  %t348 = phi ptr [%t103, %case.end.3.100], [%t347, %case.end.4.108]
  br label %case.end.4.77
case.end.4.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t349 = phi ptr [%t72, %case.end.3.69], [%t348, %case.end.4.77]
  br label %case.end.4.59
case.end.4.59:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t350 = phi ptr [%t54, %case.end.3.51], [%t349, %case.end.4.59]
  br label %case.end.4.28
case.end.4.28:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t351 = phi ptr [%t23, %case.end.3.20], [%t350, %case.end.4.28]
  %t352 = call ptr @v__let_7(ptr %t351)
  ret ptr %t352
}

define internal ptr @v__let_7(ptr %v_res) {
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
  store ptr @.str.9, ptr %t12
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

declare ptr @GetCommandLineW()
declare ptr @CommandLineToArgvW(ptr, ptr)
declare i32 @WideCharToMultiByte(i32, i32, ptr, i32, ptr, i32, ptr, ptr)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  %cmdline = call ptr @GetCommandLineW()
  %argc_slot = alloca i32
  %argv_w = call ptr @CommandLineToArgvW(ptr %cmdline, ptr %argc_slot)
  %argc_w = load i32, ptr %argc_slot
  %has_arg = icmp sgt i32 %argc_w, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %arg_w_slot = getelementptr ptr, ptr %argv_w, i64 1
  %arg_w = load ptr, ptr %arg_w_slot
  %needed = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr null, i32 0, ptr null, ptr null)
  %need_ok = icmp sgt i32 %needed, 0
  br i1 %need_ok, label %do_convert, label %no_arg
do_convert:
  %needed64 = sext i32 %needed to i64
  %buf = call ptr @malloc(i64 %needed64)
  %written = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%buf, %do_convert], [@.empty, %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
