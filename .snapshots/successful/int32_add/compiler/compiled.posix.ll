; External C declarations
declare ptr @malloc(i64)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant {i32, i32} { i32 0, i32 0 }
@.cli_arg = internal global ptr null

@.str.0 = private unnamed_addr constant {i32, i32, [14 x i8]} { i32 14, i32 14, [14 x i8] c"UnderflowError" }
@.str.1 = private unnamed_addr constant {i32, i32, [13 x i8]} { i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.2 = private unnamed_addr constant {i32, i32, [5 x i8]} { i32 5, i32 5, [5 x i8] c"err: " }
@.str.3 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 4, [4 x i8] c"ok: " }
@.str.4 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c", " }
@.str.5 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 24)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_i32, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  ret ptr %buf
}


define internal ptr @__addInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
  %sum = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %is_pos = icmp sge i32 %a, 0
  %row_tag_idx = select i1 %is_pos, i64 882564211, i64 3768445577
  %inner = call ptr @malloc(i64 8)
  %inner_tag = inttoptr i64 0 to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @malloc(i64 16)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  ret ptr %left
ok:
  %box = call ptr @malloc(i64 4)
  store i32 %sum, ptr %box
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

define internal ptr @v_showUnderflowError(ptr %v__wild0) {
  ret ptr @.str.0
}

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  ret ptr @.str.1
}

define internal ptr @v_minInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 2147483647, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.27 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 882564211, label %case.arm.882564211.14 i64 3768445577, label %case.arm.3768445577.20 ]
case.arm.882564211.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @v_showOverflowError(ptr %t17)
  %t19 = call ptr @__concat(ptr @.str.2, ptr %t18)
  br label %case.end.882564211.15
case.end.882564211.15:
  br label %case.join.13
case.arm.3768445577.20:
  %t22 = getelementptr ptr, ptr %t8, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = call ptr @v_showUnderflowError(ptr %t23)
  %t25 = call ptr @__concat(ptr @.str.2, ptr %t24)
  br label %case.end.3768445577.21
case.end.3768445577.21:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t26 = phi ptr [%t19, %case.end.882564211.15], [%t25, %case.end.3768445577.21]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.27:
  %t29 = getelementptr ptr, ptr %v_r, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @__showInt32(ptr %t30)
  %t32 = call ptr @__concat(ptr @.str.3, ptr %t31)
  br label %case.end.1.28
case.end.1.28:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t33 = phi ptr [%t26, %case.end.0.6], [%t32, %case.end.1.28]
  ret ptr %t33
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 4)
  store i32 100, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 23, ptr %t1
  %t2 = call ptr @__addInt32(ptr %t0, ptr %t1)
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
  %t21 = call ptr @malloc(i64 4)
  store i32 100, ptr %t21
  %t22 = call ptr @malloc(i64 4)
  store i32 -50, ptr %t22
  %t23 = call ptr @__addInt32(ptr %t21, ptr %t22)
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
  %t42 = call ptr @v_maxInt32()
  %t43 = call ptr @malloc(i64 4)
  store i32 1, ptr %t43
  %t44 = call ptr @__addInt32(ptr %t42, ptr %t43)
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
  %t63 = call ptr @v_minInt32()
  %t64 = call ptr @malloc(i64 4)
  store i32 -1, ptr %t64
  %t65 = call ptr @__addInt32(ptr %t63, ptr %t64)
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
  %t84 = call ptr @v_maxInt32()
  %t85 = call ptr @v_minInt32()
  %t86 = call ptr @__addInt32(ptr %t84, ptr %t85)
  %t87 = call ptr @v_render(ptr %t86)
  %t88 = getelementptr ptr, ptr %t87, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %case.default.91 [ i64 0, label %case.arm.0.93 i64 1, label %case.arm.1.101 ]
case.arm.0.93:
  %t95 = getelementptr ptr, ptr %t87, i32 1
  %t96 = load ptr, ptr %t95
  %t97 = call ptr @malloc(i64 16)
  %t98 = inttoptr i64 0 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t96, ptr %t100
  br label %case.end.0.94
case.end.0.94:
  br label %case.join.92
case.arm.1.101:
  %t103 = getelementptr ptr, ptr %t87, i32 1
  %t104 = load ptr, ptr %t103
  %t105 = call ptr @__concat(ptr %t20, ptr @.str.4)
  %t106 = getelementptr ptr, ptr %t105, i32 0
  %t107 = load ptr, ptr %t106
  %t108 = ptrtoint ptr %t107 to i64
  switch i64 %t108, label %case.default.109 [ i64 0, label %case.arm.0.111 i64 1, label %case.arm.1.119 ]
case.arm.0.111:
  %t113 = getelementptr ptr, ptr %t105, i32 1
  %t114 = load ptr, ptr %t113
  %t115 = call ptr @malloc(i64 16)
  %t116 = inttoptr i64 0 to ptr
  %t117 = getelementptr ptr, ptr %t115, i32 0
  store ptr %t116, ptr %t117
  %t118 = getelementptr ptr, ptr %t115, i32 1
  store ptr %t114, ptr %t118
  br label %case.end.0.112
case.end.0.112:
  br label %case.join.110
case.arm.1.119:
  %t121 = getelementptr ptr, ptr %t105, i32 1
  %t122 = load ptr, ptr %t121
  %t123 = call ptr @__concat(ptr %t122, ptr %t41)
  %t124 = getelementptr ptr, ptr %t123, i32 0
  %t125 = load ptr, ptr %t124
  %t126 = ptrtoint ptr %t125 to i64
  switch i64 %t126, label %case.default.127 [ i64 0, label %case.arm.0.129 i64 1, label %case.arm.1.137 ]
case.arm.0.129:
  %t131 = getelementptr ptr, ptr %t123, i32 1
  %t132 = load ptr, ptr %t131
  %t133 = call ptr @malloc(i64 16)
  %t134 = inttoptr i64 0 to ptr
  %t135 = getelementptr ptr, ptr %t133, i32 0
  store ptr %t134, ptr %t135
  %t136 = getelementptr ptr, ptr %t133, i32 1
  store ptr %t132, ptr %t136
  br label %case.end.0.130
case.end.0.130:
  br label %case.join.128
case.arm.1.137:
  %t139 = getelementptr ptr, ptr %t123, i32 1
  %t140 = load ptr, ptr %t139
  %t141 = call ptr @__concat(ptr %t140, ptr @.str.4)
  %t142 = getelementptr ptr, ptr %t141, i32 0
  %t143 = load ptr, ptr %t142
  %t144 = ptrtoint ptr %t143 to i64
  switch i64 %t144, label %case.default.145 [ i64 0, label %case.arm.0.147 i64 1, label %case.arm.1.155 ]
case.arm.0.147:
  %t149 = getelementptr ptr, ptr %t141, i32 1
  %t150 = load ptr, ptr %t149
  %t151 = call ptr @malloc(i64 16)
  %t152 = inttoptr i64 0 to ptr
  %t153 = getelementptr ptr, ptr %t151, i32 0
  store ptr %t152, ptr %t153
  %t154 = getelementptr ptr, ptr %t151, i32 1
  store ptr %t150, ptr %t154
  br label %case.end.0.148
case.end.0.148:
  br label %case.join.146
case.arm.1.155:
  %t157 = getelementptr ptr, ptr %t141, i32 1
  %t158 = load ptr, ptr %t157
  %t159 = call ptr @__concat(ptr %t158, ptr %t62)
  %t160 = getelementptr ptr, ptr %t159, i32 0
  %t161 = load ptr, ptr %t160
  %t162 = ptrtoint ptr %t161 to i64
  switch i64 %t162, label %case.default.163 [ i64 0, label %case.arm.0.165 i64 1, label %case.arm.1.173 ]
case.arm.0.165:
  %t167 = getelementptr ptr, ptr %t159, i32 1
  %t168 = load ptr, ptr %t167
  %t169 = call ptr @malloc(i64 16)
  %t170 = inttoptr i64 0 to ptr
  %t171 = getelementptr ptr, ptr %t169, i32 0
  store ptr %t170, ptr %t171
  %t172 = getelementptr ptr, ptr %t169, i32 1
  store ptr %t168, ptr %t172
  br label %case.end.0.166
case.end.0.166:
  br label %case.join.164
case.arm.1.173:
  %t175 = getelementptr ptr, ptr %t159, i32 1
  %t176 = load ptr, ptr %t175
  %t177 = call ptr @__concat(ptr %t176, ptr @.str.4)
  %t178 = getelementptr ptr, ptr %t177, i32 0
  %t179 = load ptr, ptr %t178
  %t180 = ptrtoint ptr %t179 to i64
  switch i64 %t180, label %case.default.181 [ i64 0, label %case.arm.0.183 i64 1, label %case.arm.1.191 ]
case.arm.0.183:
  %t185 = getelementptr ptr, ptr %t177, i32 1
  %t186 = load ptr, ptr %t185
  %t187 = call ptr @malloc(i64 16)
  %t188 = inttoptr i64 0 to ptr
  %t189 = getelementptr ptr, ptr %t187, i32 0
  store ptr %t188, ptr %t189
  %t190 = getelementptr ptr, ptr %t187, i32 1
  store ptr %t186, ptr %t190
  br label %case.end.0.184
case.end.0.184:
  br label %case.join.182
case.arm.1.191:
  %t193 = getelementptr ptr, ptr %t177, i32 1
  %t194 = load ptr, ptr %t193
  %t195 = call ptr @__concat(ptr %t194, ptr %t83)
  %t196 = getelementptr ptr, ptr %t195, i32 0
  %t197 = load ptr, ptr %t196
  %t198 = ptrtoint ptr %t197 to i64
  switch i64 %t198, label %case.default.199 [ i64 0, label %case.arm.0.201 i64 1, label %case.arm.1.209 ]
case.arm.0.201:
  %t203 = getelementptr ptr, ptr %t195, i32 1
  %t204 = load ptr, ptr %t203
  %t205 = call ptr @malloc(i64 16)
  %t206 = inttoptr i64 0 to ptr
  %t207 = getelementptr ptr, ptr %t205, i32 0
  store ptr %t206, ptr %t207
  %t208 = getelementptr ptr, ptr %t205, i32 1
  store ptr %t204, ptr %t208
  br label %case.end.0.202
case.end.0.202:
  br label %case.join.200
case.arm.1.209:
  %t211 = getelementptr ptr, ptr %t195, i32 1
  %t212 = load ptr, ptr %t211
  %t213 = call ptr @__concat(ptr %t212, ptr @.str.4)
  %t214 = getelementptr ptr, ptr %t213, i32 0
  %t215 = load ptr, ptr %t214
  %t216 = ptrtoint ptr %t215 to i64
  switch i64 %t216, label %case.default.217 [ i64 0, label %case.arm.0.219 i64 1, label %case.arm.1.227 ]
case.arm.0.219:
  %t221 = getelementptr ptr, ptr %t213, i32 1
  %t222 = load ptr, ptr %t221
  %t223 = call ptr @malloc(i64 16)
  %t224 = inttoptr i64 0 to ptr
  %t225 = getelementptr ptr, ptr %t223, i32 0
  store ptr %t224, ptr %t225
  %t226 = getelementptr ptr, ptr %t223, i32 1
  store ptr %t222, ptr %t226
  br label %case.end.0.220
case.end.0.220:
  br label %case.join.218
case.arm.1.227:
  %t229 = getelementptr ptr, ptr %t213, i32 1
  %t230 = load ptr, ptr %t229
  %t231 = call ptr @__concat(ptr %t230, ptr %t104)
  br label %case.end.1.228
case.end.1.228:
  br label %case.join.218
case.default.217:
  unreachable
case.join.218:
  %t232 = phi ptr [%t223, %case.end.0.220], [%t231, %case.end.1.228]
  br label %case.end.1.210
case.end.1.210:
  br label %case.join.200
case.default.199:
  unreachable
case.join.200:
  %t233 = phi ptr [%t205, %case.end.0.202], [%t232, %case.end.1.210]
  br label %case.end.1.192
case.end.1.192:
  br label %case.join.182
case.default.181:
  unreachable
case.join.182:
  %t234 = phi ptr [%t187, %case.end.0.184], [%t233, %case.end.1.192]
  br label %case.end.1.174
case.end.1.174:
  br label %case.join.164
case.default.163:
  unreachable
case.join.164:
  %t235 = phi ptr [%t169, %case.end.0.166], [%t234, %case.end.1.174]
  br label %case.end.1.156
case.end.1.156:
  br label %case.join.146
case.default.145:
  unreachable
case.join.146:
  %t236 = phi ptr [%t151, %case.end.0.148], [%t235, %case.end.1.156]
  br label %case.end.1.138
case.end.1.138:
  br label %case.join.128
case.default.127:
  unreachable
case.join.128:
  %t237 = phi ptr [%t133, %case.end.0.130], [%t236, %case.end.1.138]
  br label %case.end.1.120
case.end.1.120:
  br label %case.join.110
case.default.109:
  unreachable
case.join.110:
  %t238 = phi ptr [%t115, %case.end.0.112], [%t237, %case.end.1.120]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t239 = phi ptr [%t97, %case.end.0.94], [%t238, %case.end.1.102]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t240 = phi ptr [%t76, %case.end.0.73], [%t239, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t241 = phi ptr [%t55, %case.end.0.52], [%t240, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t242 = phi ptr [%t34, %case.end.0.31], [%t241, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t243 = phi ptr [%t13, %case.end.0.10], [%t242, %case.end.1.18]
  %t244 = call ptr @v__let_7(ptr %t243)
  ret ptr %t244
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
  store ptr @.str.5, ptr %t12
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
