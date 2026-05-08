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

@.str.0 = private unnamed_addr constant {i32, i32, [13 x i8]} { i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.1 = private unnamed_addr constant {i32, i32, [10 x i8]} { i32 10, i32 10, [10 x i8] c"overflow: " }
@.str.2 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 4, [4 x i8] c"ok: " }
@.str.3 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c", " }
@.str.4 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 24)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  ret ptr %buf
}


define internal ptr @__addUInt8(ptr %pa, ptr %pb) {
  %a = load i8, ptr %pa
  %b = load i8, ptr %pb
  %a32 = zext i8 %a to i32
  %b32 = zext i8 %b to i32
  %sum32 = add i32 %a32, %b32
  %ovf = icmp ugt i32 %sum32, 255
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @malloc(i64 8)
  %oe_tag = inttoptr i64 0 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  ret ptr %left
ok:
  %newv = trunc i32 %sum32 to i8
  %box = call ptr @malloc(i64 1)
  store i8 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
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

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  ret ptr @.str.0
}

define internal ptr @v_minUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 255, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @v_showOverflowError(ptr %t8)
  %t10 = call ptr @__concat(ptr @.str.1, ptr %t9)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_r, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__showUInt8(ptr %t14)
  %t16 = call ptr @__concat(ptr @.str.2, ptr %t15)
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t10, %case.end.0.6], [%t16, %case.end.1.12]
  ret ptr %t17
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 1)
  store i8 200, ptr %t0
  %t1 = call ptr @malloc(i64 1)
  store i8 55, ptr %t1
  %t2 = call ptr @__addUInt8(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 0, label %case.arm.0.9 i64 1, label %case.arm.1.17 ]
case.arm.0.9:
  %t11 = getelementptr ptr, ptr %t3, i32 1
  %t12 = load ptr, ptr %t11
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 0 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t12, ptr %t16
  br label %case.end.0.10
case.end.0.10:
  br label %case.join.8
case.arm.1.17:
  %t19 = getelementptr ptr, ptr %t3, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 1)
  store i8 200, ptr %t21
  %t22 = call ptr @malloc(i64 1)
  store i8 56, ptr %t22
  %t23 = call ptr @__addUInt8(ptr %t21, ptr %t22)
  %t24 = call ptr @v_render(ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 0, label %case.arm.0.30 i64 1, label %case.arm.1.38 ]
case.arm.0.30:
  %t32 = getelementptr ptr, ptr %t24, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = call ptr @malloc(i64 16)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t33, ptr %t37
  br label %case.end.0.31
case.end.0.31:
  br label %case.join.29
case.arm.1.38:
  %t40 = getelementptr ptr, ptr %t24, i32 1
  %t41 = load ptr, ptr %t40
  %t42 = call ptr @v_maxUInt8()
  %t43 = call ptr @v_maxUInt8()
  %t44 = call ptr @__addUInt8(ptr %t42, ptr %t43)
  %t45 = call ptr @v_render(ptr %t44)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 0, label %case.arm.0.51 i64 1, label %case.arm.1.59 ]
case.arm.0.51:
  %t53 = getelementptr ptr, ptr %t45, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = call ptr @malloc(i64 16)
  %t56 = inttoptr i64 0 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t54, ptr %t58
  br label %case.end.0.52
case.end.0.52:
  br label %case.join.50
case.arm.1.59:
  %t61 = getelementptr ptr, ptr %t45, i32 1
  %t62 = load ptr, ptr %t61
  %t63 = call ptr @v_minUInt8()
  %t64 = call ptr @v_minUInt8()
  %t65 = call ptr @__addUInt8(ptr %t63, ptr %t64)
  %t66 = call ptr @v_render(ptr %t65)
  %t67 = getelementptr ptr, ptr %t66, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 0, label %case.arm.0.72 i64 1, label %case.arm.1.80 ]
case.arm.0.72:
  %t74 = getelementptr ptr, ptr %t66, i32 1
  %t75 = load ptr, ptr %t74
  %t76 = call ptr @malloc(i64 16)
  %t77 = inttoptr i64 0 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  %t79 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t75, ptr %t79
  br label %case.end.0.73
case.end.0.73:
  br label %case.join.71
case.arm.1.80:
  %t82 = getelementptr ptr, ptr %t66, i32 1
  %t83 = load ptr, ptr %t82
  %t84 = call ptr @__concat(ptr %t20, ptr @.str.3)
  %t85 = getelementptr ptr, ptr %t84, i32 0
  %t86 = load ptr, ptr %t85
  %t87 = ptrtoint ptr %t86 to i64
  switch i64 %t87, label %case.default.88 [ i64 0, label %case.arm.0.90 i64 1, label %case.arm.1.98 ]
case.arm.0.90:
  %t92 = getelementptr ptr, ptr %t84, i32 1
  %t93 = load ptr, ptr %t92
  %t94 = call ptr @malloc(i64 16)
  %t95 = inttoptr i64 0 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  %t97 = getelementptr ptr, ptr %t94, i32 1
  store ptr %t93, ptr %t97
  br label %case.end.0.91
case.end.0.91:
  br label %case.join.89
case.arm.1.98:
  %t100 = getelementptr ptr, ptr %t84, i32 1
  %t101 = load ptr, ptr %t100
  %t102 = call ptr @__concat(ptr %t101, ptr %t41)
  %t103 = getelementptr ptr, ptr %t102, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 0, label %case.arm.0.108 i64 1, label %case.arm.1.116 ]
case.arm.0.108:
  %t110 = getelementptr ptr, ptr %t102, i32 1
  %t111 = load ptr, ptr %t110
  %t112 = call ptr @malloc(i64 16)
  %t113 = inttoptr i64 0 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t111, ptr %t115
  br label %case.end.0.109
case.end.0.109:
  br label %case.join.107
case.arm.1.116:
  %t118 = getelementptr ptr, ptr %t102, i32 1
  %t119 = load ptr, ptr %t118
  %t120 = call ptr @__concat(ptr %t119, ptr @.str.3)
  %t121 = getelementptr ptr, ptr %t120, i32 0
  %t122 = load ptr, ptr %t121
  %t123 = ptrtoint ptr %t122 to i64
  switch i64 %t123, label %case.default.124 [ i64 0, label %case.arm.0.126 i64 1, label %case.arm.1.134 ]
case.arm.0.126:
  %t128 = getelementptr ptr, ptr %t120, i32 1
  %t129 = load ptr, ptr %t128
  %t130 = call ptr @malloc(i64 16)
  %t131 = inttoptr i64 0 to ptr
  %t132 = getelementptr ptr, ptr %t130, i32 0
  store ptr %t131, ptr %t132
  %t133 = getelementptr ptr, ptr %t130, i32 1
  store ptr %t129, ptr %t133
  br label %case.end.0.127
case.end.0.127:
  br label %case.join.125
case.arm.1.134:
  %t136 = getelementptr ptr, ptr %t120, i32 1
  %t137 = load ptr, ptr %t136
  %t138 = call ptr @__concat(ptr %t137, ptr %t62)
  %t139 = getelementptr ptr, ptr %t138, i32 0
  %t140 = load ptr, ptr %t139
  %t141 = ptrtoint ptr %t140 to i64
  switch i64 %t141, label %case.default.142 [ i64 0, label %case.arm.0.144 i64 1, label %case.arm.1.152 ]
case.arm.0.144:
  %t146 = getelementptr ptr, ptr %t138, i32 1
  %t147 = load ptr, ptr %t146
  %t148 = call ptr @malloc(i64 16)
  %t149 = inttoptr i64 0 to ptr
  %t150 = getelementptr ptr, ptr %t148, i32 0
  store ptr %t149, ptr %t150
  %t151 = getelementptr ptr, ptr %t148, i32 1
  store ptr %t147, ptr %t151
  br label %case.end.0.145
case.end.0.145:
  br label %case.join.143
case.arm.1.152:
  %t154 = getelementptr ptr, ptr %t138, i32 1
  %t155 = load ptr, ptr %t154
  %t156 = call ptr @__concat(ptr %t155, ptr @.str.3)
  %t157 = getelementptr ptr, ptr %t156, i32 0
  %t158 = load ptr, ptr %t157
  %t159 = ptrtoint ptr %t158 to i64
  switch i64 %t159, label %case.default.160 [ i64 0, label %case.arm.0.162 i64 1, label %case.arm.1.170 ]
case.arm.0.162:
  %t164 = getelementptr ptr, ptr %t156, i32 1
  %t165 = load ptr, ptr %t164
  %t166 = call ptr @malloc(i64 16)
  %t167 = inttoptr i64 0 to ptr
  %t168 = getelementptr ptr, ptr %t166, i32 0
  store ptr %t167, ptr %t168
  %t169 = getelementptr ptr, ptr %t166, i32 1
  store ptr %t165, ptr %t169
  br label %case.end.0.163
case.end.0.163:
  br label %case.join.161
case.arm.1.170:
  %t172 = getelementptr ptr, ptr %t156, i32 1
  %t173 = load ptr, ptr %t172
  %t174 = call ptr @__concat(ptr %t173, ptr %t83)
  br label %case.end.1.171
case.end.1.171:
  br label %case.join.161
case.default.160:
  unreachable
case.join.161:
  %t175 = phi ptr [%t166, %case.end.0.163], [%t174, %case.end.1.171]
  br label %case.end.1.153
case.end.1.153:
  br label %case.join.143
case.default.142:
  unreachable
case.join.143:
  %t176 = phi ptr [%t148, %case.end.0.145], [%t175, %case.end.1.153]
  br label %case.end.1.135
case.end.1.135:
  br label %case.join.125
case.default.124:
  unreachable
case.join.125:
  %t177 = phi ptr [%t130, %case.end.0.127], [%t176, %case.end.1.135]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t178 = phi ptr [%t112, %case.end.0.109], [%t177, %case.end.1.117]
  br label %case.end.1.99
case.end.1.99:
  br label %case.join.89
case.default.88:
  unreachable
case.join.89:
  %t179 = phi ptr [%t94, %case.end.0.91], [%t178, %case.end.1.99]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t180 = phi ptr [%t76, %case.end.0.73], [%t179, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t181 = phi ptr [%t55, %case.end.0.52], [%t180, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t182 = phi ptr [%t34, %case.end.0.31], [%t181, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t183 = phi ptr [%t13, %case.end.0.10], [%t182, %case.end.1.18]
  %t184 = call ptr @v__let_7(ptr %t183)
  ret ptr %t184
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
  store ptr @.str.4, ptr %t12
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
