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


define internal ptr @__negInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
  %oe = call ptr @malloc(i64 8)
  %oe_tag = inttoptr i64 14 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  ret ptr %left
ok:
  %newv = sub i32 0, %v
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 4 to ptr
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

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  ret ptr @.str.0
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
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.11 ]
case.arm.3.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @v_showOverflowError(ptr %t8)
  %t10 = call ptr @__concat(ptr @.str.1, ptr %t9)
  br label %case.end.3.6
case.end.3.6:
  br label %case.join.4
case.arm.4.11:
  %t13 = getelementptr ptr, ptr %v_r, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__showInt32(ptr %t14)
  %t16 = call ptr @__concat(ptr @.str.2, ptr %t15)
  br label %case.end.4.12
case.end.4.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t10, %case.end.3.6], [%t16, %case.end.4.12]
  ret ptr %t17
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 4)
  store i32 5, ptr %t0
  %t1 = call ptr @__negInt32(ptr %t0)
  %t2 = call ptr @v_render(ptr %t1)
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
  store i32 -5, ptr %t20
  %t21 = call ptr @__negInt32(ptr %t20)
  %t22 = call ptr @v_render(ptr %t21)
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
  store i32 0, ptr %t40
  %t41 = call ptr @__negInt32(ptr %t40)
  %t42 = call ptr @v_render(ptr %t41)
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
  %t60 = call ptr @v_maxInt32()
  %t61 = call ptr @__negInt32(ptr %t60)
  %t62 = call ptr @v_render(ptr %t61)
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
  %t80 = call ptr @v_minInt32()
  %t81 = call ptr @__negInt32(ptr %t80)
  %t82 = call ptr @v_render(ptr %t81)
  %t83 = getelementptr ptr, ptr %t82, i32 0
  %t84 = load ptr, ptr %t83
  %t85 = ptrtoint ptr %t84 to i64
  switch i64 %t85, label %case.default.86 [ i64 3, label %case.arm.3.88 i64 4, label %case.arm.4.96 ]
case.arm.3.88:
  %t90 = getelementptr ptr, ptr %t82, i32 1
  %t91 = load ptr, ptr %t90
  %t92 = call ptr @malloc(i64 16)
  %t93 = inttoptr i64 3 to ptr
  %t94 = getelementptr ptr, ptr %t92, i32 0
  store ptr %t93, ptr %t94
  %t95 = getelementptr ptr, ptr %t92, i32 1
  store ptr %t91, ptr %t95
  br label %case.end.3.89
case.end.3.89:
  br label %case.join.87
case.arm.4.96:
  %t98 = getelementptr ptr, ptr %t82, i32 1
  %t99 = load ptr, ptr %t98
  %t100 = call ptr @__concat(ptr %t19, ptr @.str.3)
  %t101 = getelementptr ptr, ptr %t100, i32 0
  %t102 = load ptr, ptr %t101
  %t103 = ptrtoint ptr %t102 to i64
  switch i64 %t103, label %case.default.104 [ i64 3, label %case.arm.3.106 i64 4, label %case.arm.4.114 ]
case.arm.3.106:
  %t108 = getelementptr ptr, ptr %t100, i32 1
  %t109 = load ptr, ptr %t108
  %t110 = call ptr @malloc(i64 16)
  %t111 = inttoptr i64 3 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  %t113 = getelementptr ptr, ptr %t110, i32 1
  store ptr %t109, ptr %t113
  br label %case.end.3.107
case.end.3.107:
  br label %case.join.105
case.arm.4.114:
  %t116 = getelementptr ptr, ptr %t100, i32 1
  %t117 = load ptr, ptr %t116
  %t118 = call ptr @__concat(ptr %t117, ptr %t39)
  %t119 = getelementptr ptr, ptr %t118, i32 0
  %t120 = load ptr, ptr %t119
  %t121 = ptrtoint ptr %t120 to i64
  switch i64 %t121, label %case.default.122 [ i64 3, label %case.arm.3.124 i64 4, label %case.arm.4.132 ]
case.arm.3.124:
  %t126 = getelementptr ptr, ptr %t118, i32 1
  %t127 = load ptr, ptr %t126
  %t128 = call ptr @malloc(i64 16)
  %t129 = inttoptr i64 3 to ptr
  %t130 = getelementptr ptr, ptr %t128, i32 0
  store ptr %t129, ptr %t130
  %t131 = getelementptr ptr, ptr %t128, i32 1
  store ptr %t127, ptr %t131
  br label %case.end.3.125
case.end.3.125:
  br label %case.join.123
case.arm.4.132:
  %t134 = getelementptr ptr, ptr %t118, i32 1
  %t135 = load ptr, ptr %t134
  %t136 = call ptr @__concat(ptr %t135, ptr @.str.3)
  %t137 = getelementptr ptr, ptr %t136, i32 0
  %t138 = load ptr, ptr %t137
  %t139 = ptrtoint ptr %t138 to i64
  switch i64 %t139, label %case.default.140 [ i64 3, label %case.arm.3.142 i64 4, label %case.arm.4.150 ]
case.arm.3.142:
  %t144 = getelementptr ptr, ptr %t136, i32 1
  %t145 = load ptr, ptr %t144
  %t146 = call ptr @malloc(i64 16)
  %t147 = inttoptr i64 3 to ptr
  %t148 = getelementptr ptr, ptr %t146, i32 0
  store ptr %t147, ptr %t148
  %t149 = getelementptr ptr, ptr %t146, i32 1
  store ptr %t145, ptr %t149
  br label %case.end.3.143
case.end.3.143:
  br label %case.join.141
case.arm.4.150:
  %t152 = getelementptr ptr, ptr %t136, i32 1
  %t153 = load ptr, ptr %t152
  %t154 = call ptr @__concat(ptr %t153, ptr %t59)
  %t155 = getelementptr ptr, ptr %t154, i32 0
  %t156 = load ptr, ptr %t155
  %t157 = ptrtoint ptr %t156 to i64
  switch i64 %t157, label %case.default.158 [ i64 3, label %case.arm.3.160 i64 4, label %case.arm.4.168 ]
case.arm.3.160:
  %t162 = getelementptr ptr, ptr %t154, i32 1
  %t163 = load ptr, ptr %t162
  %t164 = call ptr @malloc(i64 16)
  %t165 = inttoptr i64 3 to ptr
  %t166 = getelementptr ptr, ptr %t164, i32 0
  store ptr %t165, ptr %t166
  %t167 = getelementptr ptr, ptr %t164, i32 1
  store ptr %t163, ptr %t167
  br label %case.end.3.161
case.end.3.161:
  br label %case.join.159
case.arm.4.168:
  %t170 = getelementptr ptr, ptr %t154, i32 1
  %t171 = load ptr, ptr %t170
  %t172 = call ptr @__concat(ptr %t171, ptr @.str.3)
  %t173 = getelementptr ptr, ptr %t172, i32 0
  %t174 = load ptr, ptr %t173
  %t175 = ptrtoint ptr %t174 to i64
  switch i64 %t175, label %case.default.176 [ i64 3, label %case.arm.3.178 i64 4, label %case.arm.4.186 ]
case.arm.3.178:
  %t180 = getelementptr ptr, ptr %t172, i32 1
  %t181 = load ptr, ptr %t180
  %t182 = call ptr @malloc(i64 16)
  %t183 = inttoptr i64 3 to ptr
  %t184 = getelementptr ptr, ptr %t182, i32 0
  store ptr %t183, ptr %t184
  %t185 = getelementptr ptr, ptr %t182, i32 1
  store ptr %t181, ptr %t185
  br label %case.end.3.179
case.end.3.179:
  br label %case.join.177
case.arm.4.186:
  %t188 = getelementptr ptr, ptr %t172, i32 1
  %t189 = load ptr, ptr %t188
  %t190 = call ptr @__concat(ptr %t189, ptr %t79)
  %t191 = getelementptr ptr, ptr %t190, i32 0
  %t192 = load ptr, ptr %t191
  %t193 = ptrtoint ptr %t192 to i64
  switch i64 %t193, label %case.default.194 [ i64 3, label %case.arm.3.196 i64 4, label %case.arm.4.204 ]
case.arm.3.196:
  %t198 = getelementptr ptr, ptr %t190, i32 1
  %t199 = load ptr, ptr %t198
  %t200 = call ptr @malloc(i64 16)
  %t201 = inttoptr i64 3 to ptr
  %t202 = getelementptr ptr, ptr %t200, i32 0
  store ptr %t201, ptr %t202
  %t203 = getelementptr ptr, ptr %t200, i32 1
  store ptr %t199, ptr %t203
  br label %case.end.3.197
case.end.3.197:
  br label %case.join.195
case.arm.4.204:
  %t206 = getelementptr ptr, ptr %t190, i32 1
  %t207 = load ptr, ptr %t206
  %t208 = call ptr @__concat(ptr %t207, ptr @.str.3)
  %t209 = getelementptr ptr, ptr %t208, i32 0
  %t210 = load ptr, ptr %t209
  %t211 = ptrtoint ptr %t210 to i64
  switch i64 %t211, label %case.default.212 [ i64 3, label %case.arm.3.214 i64 4, label %case.arm.4.222 ]
case.arm.3.214:
  %t216 = getelementptr ptr, ptr %t208, i32 1
  %t217 = load ptr, ptr %t216
  %t218 = call ptr @malloc(i64 16)
  %t219 = inttoptr i64 3 to ptr
  %t220 = getelementptr ptr, ptr %t218, i32 0
  store ptr %t219, ptr %t220
  %t221 = getelementptr ptr, ptr %t218, i32 1
  store ptr %t217, ptr %t221
  br label %case.end.3.215
case.end.3.215:
  br label %case.join.213
case.arm.4.222:
  %t224 = getelementptr ptr, ptr %t208, i32 1
  %t225 = load ptr, ptr %t224
  %t226 = call ptr @__concat(ptr %t225, ptr %t99)
  br label %case.end.4.223
case.end.4.223:
  br label %case.join.213
case.default.212:
  unreachable
case.join.213:
  %t227 = phi ptr [%t218, %case.end.3.215], [%t226, %case.end.4.223]
  br label %case.end.4.205
case.end.4.205:
  br label %case.join.195
case.default.194:
  unreachable
case.join.195:
  %t228 = phi ptr [%t200, %case.end.3.197], [%t227, %case.end.4.205]
  br label %case.end.4.187
case.end.4.187:
  br label %case.join.177
case.default.176:
  unreachable
case.join.177:
  %t229 = phi ptr [%t182, %case.end.3.179], [%t228, %case.end.4.187]
  br label %case.end.4.169
case.end.4.169:
  br label %case.join.159
case.default.158:
  unreachable
case.join.159:
  %t230 = phi ptr [%t164, %case.end.3.161], [%t229, %case.end.4.169]
  br label %case.end.4.151
case.end.4.151:
  br label %case.join.141
case.default.140:
  unreachable
case.join.141:
  %t231 = phi ptr [%t146, %case.end.3.143], [%t230, %case.end.4.151]
  br label %case.end.4.133
case.end.4.133:
  br label %case.join.123
case.default.122:
  unreachable
case.join.123:
  %t232 = phi ptr [%t128, %case.end.3.125], [%t231, %case.end.4.133]
  br label %case.end.4.115
case.end.4.115:
  br label %case.join.105
case.default.104:
  unreachable
case.join.105:
  %t233 = phi ptr [%t110, %case.end.3.107], [%t232, %case.end.4.115]
  br label %case.end.4.97
case.end.4.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t234 = phi ptr [%t92, %case.end.3.89], [%t233, %case.end.4.97]
  br label %case.end.4.77
case.end.4.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t235 = phi ptr [%t72, %case.end.3.69], [%t234, %case.end.4.77]
  br label %case.end.4.57
case.end.4.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t236 = phi ptr [%t52, %case.end.3.49], [%t235, %case.end.4.57]
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t237 = phi ptr [%t32, %case.end.3.29], [%t236, %case.end.4.37]
  br label %case.end.4.17
case.end.4.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t238 = phi ptr [%t12, %case.end.3.9], [%t237, %case.end.4.17]
  %t239 = call ptr @v__let_7(ptr %t238)
  ret ptr %t239
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
  store ptr @.str.4, ptr %t12
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
