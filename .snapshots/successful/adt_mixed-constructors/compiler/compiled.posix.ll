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

@.str.0 = private unnamed_addr constant {i32, i32, [5 x i8]} { i32 5, i32 5, [5 x i8] c"word:" }
@.str.1 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 4, [4 x i8] c"num:" }
@.str.2 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"," }
@.str.3 = private unnamed_addr constant {i32, i32, [5 x i8]} { i32 5, i32 5, [5 x i8] c"<eof>" }
@.str.4 = private unnamed_addr constant {i32, i32, [5 x i8]} { i32 5, i32 5, [5 x i8] c"hello" }
@.str.5 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c"42" }
@.str.6 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c" " }
@.str.7 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_showToken(ptr %v_token) {
  %t0 = getelementptr ptr, ptr %v_token, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 19, label %case.arm.19.5 i64 20, label %case.arm.20.10 i64 21, label %case.arm.21.15 i64 22, label %case.arm.22.21 ]
case.arm.19.5:
  %t7 = getelementptr ptr, ptr %v_token, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @__concat(ptr @.str.0, ptr %t8)
  br label %case.end.19.6
case.end.19.6:
  br label %case.join.4
case.arm.20.10:
  %t12 = getelementptr ptr, ptr %v_token, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @__concat(ptr @.str.1, ptr %t13)
  br label %case.end.20.11
case.end.20.11:
  br label %case.join.4
case.arm.21.15:
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 4 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr @.str.2, ptr %t20
  br label %case.end.21.16
case.end.21.16:
  br label %case.join.4
case.arm.22.21:
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 4 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr @.str.3, ptr %t26
  br label %case.end.22.22
case.end.22.22:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t27 = phi ptr [%t9, %case.end.19.6], [%t14, %case.end.20.11], [%t17, %case.end.21.16], [%t23, %case.end.22.22]
  ret ptr %t27
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 19 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr @.str.4, ptr %t3
  %t4 = call ptr @v_showToken(ptr %t0)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.18 ]
case.arm.3.10:
  %t12 = getelementptr ptr, ptr %t4, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 3 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  br label %case.end.3.11
case.end.3.11:
  br label %case.join.9
case.arm.4.18:
  %t20 = getelementptr ptr, ptr %t4, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @malloc(i64 8)
  %t23 = inttoptr i64 21 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @v_showToken(ptr %t22)
  %t26 = getelementptr ptr, ptr %t25, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.39 ]
case.arm.3.31:
  %t33 = getelementptr ptr, ptr %t25, i32 1
  %t34 = load ptr, ptr %t33
  %t35 = call ptr @malloc(i64 16)
  %t36 = inttoptr i64 3 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t34, ptr %t38
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.39:
  %t41 = getelementptr ptr, ptr %t25, i32 1
  %t42 = load ptr, ptr %t41
  %t43 = call ptr @malloc(i64 16)
  %t44 = inttoptr i64 20 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t43, i32 1
  store ptr @.str.5, ptr %t46
  %t47 = call ptr @v_showToken(ptr %t43)
  %t48 = getelementptr ptr, ptr %t47, i32 0
  %t49 = load ptr, ptr %t48
  %t50 = ptrtoint ptr %t49 to i64
  switch i64 %t50, label %case.default.51 [ i64 3, label %case.arm.3.53 i64 4, label %case.arm.4.61 ]
case.arm.3.53:
  %t55 = getelementptr ptr, ptr %t47, i32 1
  %t56 = load ptr, ptr %t55
  %t57 = call ptr @malloc(i64 16)
  %t58 = inttoptr i64 3 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t56, ptr %t60
  br label %case.end.3.54
case.end.3.54:
  br label %case.join.52
case.arm.4.61:
  %t63 = getelementptr ptr, ptr %t47, i32 1
  %t64 = load ptr, ptr %t63
  %t65 = call ptr @malloc(i64 8)
  %t66 = inttoptr i64 22 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @v_showToken(ptr %t65)
  %t69 = getelementptr ptr, ptr %t68, i32 0
  %t70 = load ptr, ptr %t69
  %t71 = ptrtoint ptr %t70 to i64
  switch i64 %t71, label %case.default.72 [ i64 3, label %case.arm.3.74 i64 4, label %case.arm.4.82 ]
case.arm.3.74:
  %t76 = getelementptr ptr, ptr %t68, i32 1
  %t77 = load ptr, ptr %t76
  %t78 = call ptr @malloc(i64 16)
  %t79 = inttoptr i64 3 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t77, ptr %t81
  br label %case.end.3.75
case.end.3.75:
  br label %case.join.73
case.arm.4.82:
  %t84 = getelementptr ptr, ptr %t68, i32 1
  %t85 = load ptr, ptr %t84
  %t86 = call ptr @__concat(ptr %t21, ptr @.str.6)
  %t87 = getelementptr ptr, ptr %t86, i32 0
  %t88 = load ptr, ptr %t87
  %t89 = ptrtoint ptr %t88 to i64
  switch i64 %t89, label %case.default.90 [ i64 3, label %case.arm.3.92 i64 4, label %case.arm.4.100 ]
case.arm.3.92:
  %t94 = getelementptr ptr, ptr %t86, i32 1
  %t95 = load ptr, ptr %t94
  %t96 = call ptr @malloc(i64 16)
  %t97 = inttoptr i64 3 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  %t99 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t95, ptr %t99
  br label %case.end.3.93
case.end.3.93:
  br label %case.join.91
case.arm.4.100:
  %t102 = getelementptr ptr, ptr %t86, i32 1
  %t103 = load ptr, ptr %t102
  %t104 = call ptr @__concat(ptr %t103, ptr %t42)
  %t105 = getelementptr ptr, ptr %t104, i32 0
  %t106 = load ptr, ptr %t105
  %t107 = ptrtoint ptr %t106 to i64
  switch i64 %t107, label %case.default.108 [ i64 3, label %case.arm.3.110 i64 4, label %case.arm.4.118 ]
case.arm.3.110:
  %t112 = getelementptr ptr, ptr %t104, i32 1
  %t113 = load ptr, ptr %t112
  %t114 = call ptr @malloc(i64 16)
  %t115 = inttoptr i64 3 to ptr
  %t116 = getelementptr ptr, ptr %t114, i32 0
  store ptr %t115, ptr %t116
  %t117 = getelementptr ptr, ptr %t114, i32 1
  store ptr %t113, ptr %t117
  br label %case.end.3.111
case.end.3.111:
  br label %case.join.109
case.arm.4.118:
  %t120 = getelementptr ptr, ptr %t104, i32 1
  %t121 = load ptr, ptr %t120
  %t122 = call ptr @__concat(ptr %t121, ptr @.str.6)
  %t123 = getelementptr ptr, ptr %t122, i32 0
  %t124 = load ptr, ptr %t123
  %t125 = ptrtoint ptr %t124 to i64
  switch i64 %t125, label %case.default.126 [ i64 3, label %case.arm.3.128 i64 4, label %case.arm.4.136 ]
case.arm.3.128:
  %t130 = getelementptr ptr, ptr %t122, i32 1
  %t131 = load ptr, ptr %t130
  %t132 = call ptr @malloc(i64 16)
  %t133 = inttoptr i64 3 to ptr
  %t134 = getelementptr ptr, ptr %t132, i32 0
  store ptr %t133, ptr %t134
  %t135 = getelementptr ptr, ptr %t132, i32 1
  store ptr %t131, ptr %t135
  br label %case.end.3.129
case.end.3.129:
  br label %case.join.127
case.arm.4.136:
  %t138 = getelementptr ptr, ptr %t122, i32 1
  %t139 = load ptr, ptr %t138
  %t140 = call ptr @__concat(ptr %t139, ptr %t64)
  %t141 = getelementptr ptr, ptr %t140, i32 0
  %t142 = load ptr, ptr %t141
  %t143 = ptrtoint ptr %t142 to i64
  switch i64 %t143, label %case.default.144 [ i64 3, label %case.arm.3.146 i64 4, label %case.arm.4.154 ]
case.arm.3.146:
  %t148 = getelementptr ptr, ptr %t140, i32 1
  %t149 = load ptr, ptr %t148
  %t150 = call ptr @malloc(i64 16)
  %t151 = inttoptr i64 3 to ptr
  %t152 = getelementptr ptr, ptr %t150, i32 0
  store ptr %t151, ptr %t152
  %t153 = getelementptr ptr, ptr %t150, i32 1
  store ptr %t149, ptr %t153
  br label %case.end.3.147
case.end.3.147:
  br label %case.join.145
case.arm.4.154:
  %t156 = getelementptr ptr, ptr %t140, i32 1
  %t157 = load ptr, ptr %t156
  %t158 = call ptr @__concat(ptr %t157, ptr @.str.6)
  %t159 = getelementptr ptr, ptr %t158, i32 0
  %t160 = load ptr, ptr %t159
  %t161 = ptrtoint ptr %t160 to i64
  switch i64 %t161, label %case.default.162 [ i64 3, label %case.arm.3.164 i64 4, label %case.arm.4.172 ]
case.arm.3.164:
  %t166 = getelementptr ptr, ptr %t158, i32 1
  %t167 = load ptr, ptr %t166
  %t168 = call ptr @malloc(i64 16)
  %t169 = inttoptr i64 3 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  %t171 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t167, ptr %t171
  br label %case.end.3.165
case.end.3.165:
  br label %case.join.163
case.arm.4.172:
  %t174 = getelementptr ptr, ptr %t158, i32 1
  %t175 = load ptr, ptr %t174
  %t176 = call ptr @__concat(ptr %t175, ptr %t85)
  br label %case.end.4.173
case.end.4.173:
  br label %case.join.163
case.default.162:
  unreachable
case.join.163:
  %t177 = phi ptr [%t168, %case.end.3.165], [%t176, %case.end.4.173]
  br label %case.end.4.155
case.end.4.155:
  br label %case.join.145
case.default.144:
  unreachable
case.join.145:
  %t178 = phi ptr [%t150, %case.end.3.147], [%t177, %case.end.4.155]
  br label %case.end.4.137
case.end.4.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t179 = phi ptr [%t132, %case.end.3.129], [%t178, %case.end.4.137]
  br label %case.end.4.119
case.end.4.119:
  br label %case.join.109
case.default.108:
  unreachable
case.join.109:
  %t180 = phi ptr [%t114, %case.end.3.111], [%t179, %case.end.4.119]
  br label %case.end.4.101
case.end.4.101:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t181 = phi ptr [%t96, %case.end.3.93], [%t180, %case.end.4.101]
  br label %case.end.4.83
case.end.4.83:
  br label %case.join.73
case.default.72:
  unreachable
case.join.73:
  %t182 = phi ptr [%t78, %case.end.3.75], [%t181, %case.end.4.83]
  br label %case.end.4.62
case.end.4.62:
  br label %case.join.52
case.default.51:
  unreachable
case.join.52:
  %t183 = phi ptr [%t57, %case.end.3.54], [%t182, %case.end.4.62]
  br label %case.end.4.40
case.end.4.40:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t184 = phi ptr [%t35, %case.end.3.32], [%t183, %case.end.4.40]
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t185 = phi ptr [%t14, %case.end.3.11], [%t184, %case.end.4.19]
  %t186 = call ptr @v__let_7(ptr %t185)
  ret ptr %t186
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
  store ptr @.str.7, ptr %t12
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
