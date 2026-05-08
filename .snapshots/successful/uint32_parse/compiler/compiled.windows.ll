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

@.str.0 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"err" }
@.str.1 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"ok:" }
@.str.2 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"0" }
@.str.3 = private unnamed_addr constant {i32, i32, [10 x i8]} { i32 10, i32 10, [10 x i8] c"4294967295" }
@.str.4 = private unnamed_addr constant {i32, i32, [10 x i8]} { i32 10, i32 10, [10 x i8] c"4294967296" }
@.str.5 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c"-1" }
@.str.6 = private unnamed_addr constant {i32, i32, [0 x i8]} { i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.7 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"abc" }
@.str.8 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c" 5" }
@.str.9 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"12a" }
@.str.10 = private unnamed_addr constant {i32, i32, [10 x i8]} { i32 10, i32 10, [10 x i8] c"2147483648" }
@.str.11 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c", " }
@.str.12 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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


define internal ptr @__parseUInt32(ptr %s) {
entry:
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i64, align 8
  store i64 0, ptr %acc_alloca
  %len32 = load i32, ptr %s
  %len = zext i32 %len32 to i64
  %payload = getelementptr i8, ptr %s, i64 8
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i64, ptr %acc_alloca
  %cond = icmp ult i64 %i, %len
  br i1 %cond, label %body, label %ok
body:
  %ptr_c = getelementptr i8, ptr %payload, i64 %i
  %c = load i8, ptr %ptr_c
  %c_i32 = zext i8 %c to i32
  %low = icmp ult i32 %c_i32, 48
  %high = icmp ugt i32 %c_i32, 57
  %bad = or i1 %low, %high
  br i1 %bad, label %fail, label %parse
parse:
  %d = sub i32 %c_i32, 48
  %d_i64 = zext i32 %d to i64
  %x10 = mul i64 %acc, 10
  %acc_next = add i64 %x10, %d_i64
  %big = icmp ugt i64 %acc_next, 4294967295
  br i1 %big, label %fail, label %body_end
body_end:
  store i64 %acc_next, ptr %acc_alloca
  %i_next = add i64 %i, 1
  store i64 %i_next, ptr %i_alloca
  br label %loop_head
ok:
  %result_i32 = trunc i64 %acc to i32
  %box = call ptr @malloc(i64 4)
  store i32 %result_i32, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
fail:
  %pe = call ptr @malloc(i64 8)
  %pe_tag = inttoptr i64 0 to ptr
  store ptr %pe_tag, ptr %pe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %pe, ptr %left_f
  ret ptr %left
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

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.13 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr @.str.0, ptr %t12
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.13:
  %t15 = getelementptr ptr, ptr %v_r, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @__showUInt32(ptr %t16)
  %t18 = call ptr @__concat(ptr @.str.1, ptr %t17)
  br label %case.end.1.14
case.end.1.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t19 = phi ptr [%t9, %case.end.0.6], [%t18, %case.end.1.14]
  ret ptr %t19
}

define internal ptr @v_main() {
  %t0 = call ptr @__parseUInt32(ptr @.str.2)
  %t1 = call ptr @v_render(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 0, label %case.arm.0.7 i64 1, label %case.arm.1.15 ]
case.arm.0.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 16)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  br label %case.end.0.8
case.end.0.8:
  br label %case.join.6
case.arm.1.15:
  %t17 = getelementptr ptr, ptr %t1, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = call ptr @__parseUInt32(ptr @.str.3)
  %t20 = call ptr @v_render(ptr %t19)
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %case.default.24 [ i64 0, label %case.arm.0.26 i64 1, label %case.arm.1.34 ]
case.arm.0.26:
  %t28 = getelementptr ptr, ptr %t20, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t29, ptr %t33
  br label %case.end.0.27
case.end.0.27:
  br label %case.join.25
case.arm.1.34:
  %t36 = getelementptr ptr, ptr %t20, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = call ptr @__parseUInt32(ptr @.str.4)
  %t39 = call ptr @v_render(ptr %t38)
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 0, label %case.arm.0.45 i64 1, label %case.arm.1.53 ]
case.arm.0.45:
  %t47 = getelementptr ptr, ptr %t39, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = call ptr @malloc(i64 16)
  %t50 = inttoptr i64 0 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t48, ptr %t52
  br label %case.end.0.46
case.end.0.46:
  br label %case.join.44
case.arm.1.53:
  %t55 = getelementptr ptr, ptr %t39, i32 1
  %t56 = load ptr, ptr %t55
  %t57 = call ptr @__parseUInt32(ptr @.str.5)
  %t58 = call ptr @v_render(ptr %t57)
  %t59 = getelementptr ptr, ptr %t58, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %case.default.62 [ i64 0, label %case.arm.0.64 i64 1, label %case.arm.1.72 ]
case.arm.0.64:
  %t66 = getelementptr ptr, ptr %t58, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  br label %case.end.0.65
case.end.0.65:
  br label %case.join.63
case.arm.1.72:
  %t74 = getelementptr ptr, ptr %t58, i32 1
  %t75 = load ptr, ptr %t74
  %t76 = call ptr @__parseUInt32(ptr @.str.6)
  %t77 = call ptr @v_render(ptr %t76)
  %t78 = getelementptr ptr, ptr %t77, i32 0
  %t79 = load ptr, ptr %t78
  %t80 = ptrtoint ptr %t79 to i64
  switch i64 %t80, label %case.default.81 [ i64 0, label %case.arm.0.83 i64 1, label %case.arm.1.91 ]
case.arm.0.83:
  %t85 = getelementptr ptr, ptr %t77, i32 1
  %t86 = load ptr, ptr %t85
  %t87 = call ptr @malloc(i64 16)
  %t88 = inttoptr i64 0 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  %t90 = getelementptr ptr, ptr %t87, i32 1
  store ptr %t86, ptr %t90
  br label %case.end.0.84
case.end.0.84:
  br label %case.join.82
case.arm.1.91:
  %t93 = getelementptr ptr, ptr %t77, i32 1
  %t94 = load ptr, ptr %t93
  %t95 = call ptr @__parseUInt32(ptr @.str.7)
  %t96 = call ptr @v_render(ptr %t95)
  %t97 = getelementptr ptr, ptr %t96, i32 0
  %t98 = load ptr, ptr %t97
  %t99 = ptrtoint ptr %t98 to i64
  switch i64 %t99, label %case.default.100 [ i64 0, label %case.arm.0.102 i64 1, label %case.arm.1.110 ]
case.arm.0.102:
  %t104 = getelementptr ptr, ptr %t96, i32 1
  %t105 = load ptr, ptr %t104
  %t106 = call ptr @malloc(i64 16)
  %t107 = inttoptr i64 0 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  %t109 = getelementptr ptr, ptr %t106, i32 1
  store ptr %t105, ptr %t109
  br label %case.end.0.103
case.end.0.103:
  br label %case.join.101
case.arm.1.110:
  %t112 = getelementptr ptr, ptr %t96, i32 1
  %t113 = load ptr, ptr %t112
  %t114 = call ptr @__parseUInt32(ptr @.str.8)
  %t115 = call ptr @v_render(ptr %t114)
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
  %t133 = call ptr @__parseUInt32(ptr @.str.9)
  %t134 = call ptr @v_render(ptr %t133)
  %t135 = getelementptr ptr, ptr %t134, i32 0
  %t136 = load ptr, ptr %t135
  %t137 = ptrtoint ptr %t136 to i64
  switch i64 %t137, label %case.default.138 [ i64 0, label %case.arm.0.140 i64 1, label %case.arm.1.148 ]
case.arm.0.140:
  %t142 = getelementptr ptr, ptr %t134, i32 1
  %t143 = load ptr, ptr %t142
  %t144 = call ptr @malloc(i64 16)
  %t145 = inttoptr i64 0 to ptr
  %t146 = getelementptr ptr, ptr %t144, i32 0
  store ptr %t145, ptr %t146
  %t147 = getelementptr ptr, ptr %t144, i32 1
  store ptr %t143, ptr %t147
  br label %case.end.0.141
case.end.0.141:
  br label %case.join.139
case.arm.1.148:
  %t150 = getelementptr ptr, ptr %t134, i32 1
  %t151 = load ptr, ptr %t150
  %t152 = call ptr @__parseUInt32(ptr @.str.10)
  %t153 = call ptr @v_render(ptr %t152)
  %t154 = getelementptr ptr, ptr %t153, i32 0
  %t155 = load ptr, ptr %t154
  %t156 = ptrtoint ptr %t155 to i64
  switch i64 %t156, label %case.default.157 [ i64 0, label %case.arm.0.159 i64 1, label %case.arm.1.167 ]
case.arm.0.159:
  %t161 = getelementptr ptr, ptr %t153, i32 1
  %t162 = load ptr, ptr %t161
  %t163 = call ptr @malloc(i64 16)
  %t164 = inttoptr i64 0 to ptr
  %t165 = getelementptr ptr, ptr %t163, i32 0
  store ptr %t164, ptr %t165
  %t166 = getelementptr ptr, ptr %t163, i32 1
  store ptr %t162, ptr %t166
  br label %case.end.0.160
case.end.0.160:
  br label %case.join.158
case.arm.1.167:
  %t169 = getelementptr ptr, ptr %t153, i32 1
  %t170 = load ptr, ptr %t169
  %t171 = call ptr @__concat(ptr %t18, ptr @.str.11)
  %t172 = getelementptr ptr, ptr %t171, i32 0
  %t173 = load ptr, ptr %t172
  %t174 = ptrtoint ptr %t173 to i64
  switch i64 %t174, label %case.default.175 [ i64 0, label %case.arm.0.177 i64 1, label %case.arm.1.185 ]
case.arm.0.177:
  %t179 = getelementptr ptr, ptr %t171, i32 1
  %t180 = load ptr, ptr %t179
  %t181 = call ptr @malloc(i64 16)
  %t182 = inttoptr i64 0 to ptr
  %t183 = getelementptr ptr, ptr %t181, i32 0
  store ptr %t182, ptr %t183
  %t184 = getelementptr ptr, ptr %t181, i32 1
  store ptr %t180, ptr %t184
  br label %case.end.0.178
case.end.0.178:
  br label %case.join.176
case.arm.1.185:
  %t187 = getelementptr ptr, ptr %t171, i32 1
  %t188 = load ptr, ptr %t187
  %t189 = call ptr @__concat(ptr %t188, ptr %t37)
  %t190 = getelementptr ptr, ptr %t189, i32 0
  %t191 = load ptr, ptr %t190
  %t192 = ptrtoint ptr %t191 to i64
  switch i64 %t192, label %case.default.193 [ i64 0, label %case.arm.0.195 i64 1, label %case.arm.1.203 ]
case.arm.0.195:
  %t197 = getelementptr ptr, ptr %t189, i32 1
  %t198 = load ptr, ptr %t197
  %t199 = call ptr @malloc(i64 16)
  %t200 = inttoptr i64 0 to ptr
  %t201 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t200, ptr %t201
  %t202 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t198, ptr %t202
  br label %case.end.0.196
case.end.0.196:
  br label %case.join.194
case.arm.1.203:
  %t205 = getelementptr ptr, ptr %t189, i32 1
  %t206 = load ptr, ptr %t205
  %t207 = call ptr @__concat(ptr %t206, ptr @.str.11)
  %t208 = getelementptr ptr, ptr %t207, i32 0
  %t209 = load ptr, ptr %t208
  %t210 = ptrtoint ptr %t209 to i64
  switch i64 %t210, label %case.default.211 [ i64 0, label %case.arm.0.213 i64 1, label %case.arm.1.221 ]
case.arm.0.213:
  %t215 = getelementptr ptr, ptr %t207, i32 1
  %t216 = load ptr, ptr %t215
  %t217 = call ptr @malloc(i64 16)
  %t218 = inttoptr i64 0 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  %t220 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t216, ptr %t220
  br label %case.end.0.214
case.end.0.214:
  br label %case.join.212
case.arm.1.221:
  %t223 = getelementptr ptr, ptr %t207, i32 1
  %t224 = load ptr, ptr %t223
  %t225 = call ptr @__concat(ptr %t224, ptr %t56)
  %t226 = getelementptr ptr, ptr %t225, i32 0
  %t227 = load ptr, ptr %t226
  %t228 = ptrtoint ptr %t227 to i64
  switch i64 %t228, label %case.default.229 [ i64 0, label %case.arm.0.231 i64 1, label %case.arm.1.239 ]
case.arm.0.231:
  %t233 = getelementptr ptr, ptr %t225, i32 1
  %t234 = load ptr, ptr %t233
  %t235 = call ptr @malloc(i64 16)
  %t236 = inttoptr i64 0 to ptr
  %t237 = getelementptr ptr, ptr %t235, i32 0
  store ptr %t236, ptr %t237
  %t238 = getelementptr ptr, ptr %t235, i32 1
  store ptr %t234, ptr %t238
  br label %case.end.0.232
case.end.0.232:
  br label %case.join.230
case.arm.1.239:
  %t241 = getelementptr ptr, ptr %t225, i32 1
  %t242 = load ptr, ptr %t241
  %t243 = call ptr @__concat(ptr %t242, ptr @.str.11)
  %t244 = getelementptr ptr, ptr %t243, i32 0
  %t245 = load ptr, ptr %t244
  %t246 = ptrtoint ptr %t245 to i64
  switch i64 %t246, label %case.default.247 [ i64 0, label %case.arm.0.249 i64 1, label %case.arm.1.257 ]
case.arm.0.249:
  %t251 = getelementptr ptr, ptr %t243, i32 1
  %t252 = load ptr, ptr %t251
  %t253 = call ptr @malloc(i64 16)
  %t254 = inttoptr i64 0 to ptr
  %t255 = getelementptr ptr, ptr %t253, i32 0
  store ptr %t254, ptr %t255
  %t256 = getelementptr ptr, ptr %t253, i32 1
  store ptr %t252, ptr %t256
  br label %case.end.0.250
case.end.0.250:
  br label %case.join.248
case.arm.1.257:
  %t259 = getelementptr ptr, ptr %t243, i32 1
  %t260 = load ptr, ptr %t259
  %t261 = call ptr @__concat(ptr %t260, ptr %t75)
  %t262 = getelementptr ptr, ptr %t261, i32 0
  %t263 = load ptr, ptr %t262
  %t264 = ptrtoint ptr %t263 to i64
  switch i64 %t264, label %case.default.265 [ i64 0, label %case.arm.0.267 i64 1, label %case.arm.1.275 ]
case.arm.0.267:
  %t269 = getelementptr ptr, ptr %t261, i32 1
  %t270 = load ptr, ptr %t269
  %t271 = call ptr @malloc(i64 16)
  %t272 = inttoptr i64 0 to ptr
  %t273 = getelementptr ptr, ptr %t271, i32 0
  store ptr %t272, ptr %t273
  %t274 = getelementptr ptr, ptr %t271, i32 1
  store ptr %t270, ptr %t274
  br label %case.end.0.268
case.end.0.268:
  br label %case.join.266
case.arm.1.275:
  %t277 = getelementptr ptr, ptr %t261, i32 1
  %t278 = load ptr, ptr %t277
  %t279 = call ptr @__concat(ptr %t278, ptr @.str.11)
  %t280 = getelementptr ptr, ptr %t279, i32 0
  %t281 = load ptr, ptr %t280
  %t282 = ptrtoint ptr %t281 to i64
  switch i64 %t282, label %case.default.283 [ i64 0, label %case.arm.0.285 i64 1, label %case.arm.1.293 ]
case.arm.0.285:
  %t287 = getelementptr ptr, ptr %t279, i32 1
  %t288 = load ptr, ptr %t287
  %t289 = call ptr @malloc(i64 16)
  %t290 = inttoptr i64 0 to ptr
  %t291 = getelementptr ptr, ptr %t289, i32 0
  store ptr %t290, ptr %t291
  %t292 = getelementptr ptr, ptr %t289, i32 1
  store ptr %t288, ptr %t292
  br label %case.end.0.286
case.end.0.286:
  br label %case.join.284
case.arm.1.293:
  %t295 = getelementptr ptr, ptr %t279, i32 1
  %t296 = load ptr, ptr %t295
  %t297 = call ptr @__concat(ptr %t296, ptr %t94)
  %t298 = getelementptr ptr, ptr %t297, i32 0
  %t299 = load ptr, ptr %t298
  %t300 = ptrtoint ptr %t299 to i64
  switch i64 %t300, label %case.default.301 [ i64 0, label %case.arm.0.303 i64 1, label %case.arm.1.311 ]
case.arm.0.303:
  %t305 = getelementptr ptr, ptr %t297, i32 1
  %t306 = load ptr, ptr %t305
  %t307 = call ptr @malloc(i64 16)
  %t308 = inttoptr i64 0 to ptr
  %t309 = getelementptr ptr, ptr %t307, i32 0
  store ptr %t308, ptr %t309
  %t310 = getelementptr ptr, ptr %t307, i32 1
  store ptr %t306, ptr %t310
  br label %case.end.0.304
case.end.0.304:
  br label %case.join.302
case.arm.1.311:
  %t313 = getelementptr ptr, ptr %t297, i32 1
  %t314 = load ptr, ptr %t313
  %t315 = call ptr @__concat(ptr %t314, ptr @.str.11)
  %t316 = getelementptr ptr, ptr %t315, i32 0
  %t317 = load ptr, ptr %t316
  %t318 = ptrtoint ptr %t317 to i64
  switch i64 %t318, label %case.default.319 [ i64 0, label %case.arm.0.321 i64 1, label %case.arm.1.329 ]
case.arm.0.321:
  %t323 = getelementptr ptr, ptr %t315, i32 1
  %t324 = load ptr, ptr %t323
  %t325 = call ptr @malloc(i64 16)
  %t326 = inttoptr i64 0 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  %t328 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t324, ptr %t328
  br label %case.end.0.322
case.end.0.322:
  br label %case.join.320
case.arm.1.329:
  %t331 = getelementptr ptr, ptr %t315, i32 1
  %t332 = load ptr, ptr %t331
  %t333 = call ptr @__concat(ptr %t332, ptr %t113)
  %t334 = getelementptr ptr, ptr %t333, i32 0
  %t335 = load ptr, ptr %t334
  %t336 = ptrtoint ptr %t335 to i64
  switch i64 %t336, label %case.default.337 [ i64 0, label %case.arm.0.339 i64 1, label %case.arm.1.347 ]
case.arm.0.339:
  %t341 = getelementptr ptr, ptr %t333, i32 1
  %t342 = load ptr, ptr %t341
  %t343 = call ptr @malloc(i64 16)
  %t344 = inttoptr i64 0 to ptr
  %t345 = getelementptr ptr, ptr %t343, i32 0
  store ptr %t344, ptr %t345
  %t346 = getelementptr ptr, ptr %t343, i32 1
  store ptr %t342, ptr %t346
  br label %case.end.0.340
case.end.0.340:
  br label %case.join.338
case.arm.1.347:
  %t349 = getelementptr ptr, ptr %t333, i32 1
  %t350 = load ptr, ptr %t349
  %t351 = call ptr @__concat(ptr %t350, ptr @.str.11)
  %t352 = getelementptr ptr, ptr %t351, i32 0
  %t353 = load ptr, ptr %t352
  %t354 = ptrtoint ptr %t353 to i64
  switch i64 %t354, label %case.default.355 [ i64 0, label %case.arm.0.357 i64 1, label %case.arm.1.365 ]
case.arm.0.357:
  %t359 = getelementptr ptr, ptr %t351, i32 1
  %t360 = load ptr, ptr %t359
  %t361 = call ptr @malloc(i64 16)
  %t362 = inttoptr i64 0 to ptr
  %t363 = getelementptr ptr, ptr %t361, i32 0
  store ptr %t362, ptr %t363
  %t364 = getelementptr ptr, ptr %t361, i32 1
  store ptr %t360, ptr %t364
  br label %case.end.0.358
case.end.0.358:
  br label %case.join.356
case.arm.1.365:
  %t367 = getelementptr ptr, ptr %t351, i32 1
  %t368 = load ptr, ptr %t367
  %t369 = call ptr @__concat(ptr %t368, ptr %t132)
  %t370 = getelementptr ptr, ptr %t369, i32 0
  %t371 = load ptr, ptr %t370
  %t372 = ptrtoint ptr %t371 to i64
  switch i64 %t372, label %case.default.373 [ i64 0, label %case.arm.0.375 i64 1, label %case.arm.1.383 ]
case.arm.0.375:
  %t377 = getelementptr ptr, ptr %t369, i32 1
  %t378 = load ptr, ptr %t377
  %t379 = call ptr @malloc(i64 16)
  %t380 = inttoptr i64 0 to ptr
  %t381 = getelementptr ptr, ptr %t379, i32 0
  store ptr %t380, ptr %t381
  %t382 = getelementptr ptr, ptr %t379, i32 1
  store ptr %t378, ptr %t382
  br label %case.end.0.376
case.end.0.376:
  br label %case.join.374
case.arm.1.383:
  %t385 = getelementptr ptr, ptr %t369, i32 1
  %t386 = load ptr, ptr %t385
  %t387 = call ptr @__concat(ptr %t386, ptr @.str.11)
  %t388 = getelementptr ptr, ptr %t387, i32 0
  %t389 = load ptr, ptr %t388
  %t390 = ptrtoint ptr %t389 to i64
  switch i64 %t390, label %case.default.391 [ i64 0, label %case.arm.0.393 i64 1, label %case.arm.1.401 ]
case.arm.0.393:
  %t395 = getelementptr ptr, ptr %t387, i32 1
  %t396 = load ptr, ptr %t395
  %t397 = call ptr @malloc(i64 16)
  %t398 = inttoptr i64 0 to ptr
  %t399 = getelementptr ptr, ptr %t397, i32 0
  store ptr %t398, ptr %t399
  %t400 = getelementptr ptr, ptr %t397, i32 1
  store ptr %t396, ptr %t400
  br label %case.end.0.394
case.end.0.394:
  br label %case.join.392
case.arm.1.401:
  %t403 = getelementptr ptr, ptr %t387, i32 1
  %t404 = load ptr, ptr %t403
  %t405 = call ptr @__concat(ptr %t404, ptr %t151)
  %t406 = getelementptr ptr, ptr %t405, i32 0
  %t407 = load ptr, ptr %t406
  %t408 = ptrtoint ptr %t407 to i64
  switch i64 %t408, label %case.default.409 [ i64 0, label %case.arm.0.411 i64 1, label %case.arm.1.419 ]
case.arm.0.411:
  %t413 = getelementptr ptr, ptr %t405, i32 1
  %t414 = load ptr, ptr %t413
  %t415 = call ptr @malloc(i64 16)
  %t416 = inttoptr i64 0 to ptr
  %t417 = getelementptr ptr, ptr %t415, i32 0
  store ptr %t416, ptr %t417
  %t418 = getelementptr ptr, ptr %t415, i32 1
  store ptr %t414, ptr %t418
  br label %case.end.0.412
case.end.0.412:
  br label %case.join.410
case.arm.1.419:
  %t421 = getelementptr ptr, ptr %t405, i32 1
  %t422 = load ptr, ptr %t421
  %t423 = call ptr @__concat(ptr %t422, ptr @.str.11)
  %t424 = getelementptr ptr, ptr %t423, i32 0
  %t425 = load ptr, ptr %t424
  %t426 = ptrtoint ptr %t425 to i64
  switch i64 %t426, label %case.default.427 [ i64 0, label %case.arm.0.429 i64 1, label %case.arm.1.437 ]
case.arm.0.429:
  %t431 = getelementptr ptr, ptr %t423, i32 1
  %t432 = load ptr, ptr %t431
  %t433 = call ptr @malloc(i64 16)
  %t434 = inttoptr i64 0 to ptr
  %t435 = getelementptr ptr, ptr %t433, i32 0
  store ptr %t434, ptr %t435
  %t436 = getelementptr ptr, ptr %t433, i32 1
  store ptr %t432, ptr %t436
  br label %case.end.0.430
case.end.0.430:
  br label %case.join.428
case.arm.1.437:
  %t439 = getelementptr ptr, ptr %t423, i32 1
  %t440 = load ptr, ptr %t439
  %t441 = call ptr @__concat(ptr %t440, ptr %t170)
  br label %case.end.1.438
case.end.1.438:
  br label %case.join.428
case.default.427:
  unreachable
case.join.428:
  %t442 = phi ptr [%t433, %case.end.0.430], [%t441, %case.end.1.438]
  br label %case.end.1.420
case.end.1.420:
  br label %case.join.410
case.default.409:
  unreachable
case.join.410:
  %t443 = phi ptr [%t415, %case.end.0.412], [%t442, %case.end.1.420]
  br label %case.end.1.402
case.end.1.402:
  br label %case.join.392
case.default.391:
  unreachable
case.join.392:
  %t444 = phi ptr [%t397, %case.end.0.394], [%t443, %case.end.1.402]
  br label %case.end.1.384
case.end.1.384:
  br label %case.join.374
case.default.373:
  unreachable
case.join.374:
  %t445 = phi ptr [%t379, %case.end.0.376], [%t444, %case.end.1.384]
  br label %case.end.1.366
case.end.1.366:
  br label %case.join.356
case.default.355:
  unreachable
case.join.356:
  %t446 = phi ptr [%t361, %case.end.0.358], [%t445, %case.end.1.366]
  br label %case.end.1.348
case.end.1.348:
  br label %case.join.338
case.default.337:
  unreachable
case.join.338:
  %t447 = phi ptr [%t343, %case.end.0.340], [%t446, %case.end.1.348]
  br label %case.end.1.330
case.end.1.330:
  br label %case.join.320
case.default.319:
  unreachable
case.join.320:
  %t448 = phi ptr [%t325, %case.end.0.322], [%t447, %case.end.1.330]
  br label %case.end.1.312
case.end.1.312:
  br label %case.join.302
case.default.301:
  unreachable
case.join.302:
  %t449 = phi ptr [%t307, %case.end.0.304], [%t448, %case.end.1.312]
  br label %case.end.1.294
case.end.1.294:
  br label %case.join.284
case.default.283:
  unreachable
case.join.284:
  %t450 = phi ptr [%t289, %case.end.0.286], [%t449, %case.end.1.294]
  br label %case.end.1.276
case.end.1.276:
  br label %case.join.266
case.default.265:
  unreachable
case.join.266:
  %t451 = phi ptr [%t271, %case.end.0.268], [%t450, %case.end.1.276]
  br label %case.end.1.258
case.end.1.258:
  br label %case.join.248
case.default.247:
  unreachable
case.join.248:
  %t452 = phi ptr [%t253, %case.end.0.250], [%t451, %case.end.1.258]
  br label %case.end.1.240
case.end.1.240:
  br label %case.join.230
case.default.229:
  unreachable
case.join.230:
  %t453 = phi ptr [%t235, %case.end.0.232], [%t452, %case.end.1.240]
  br label %case.end.1.222
case.end.1.222:
  br label %case.join.212
case.default.211:
  unreachable
case.join.212:
  %t454 = phi ptr [%t217, %case.end.0.214], [%t453, %case.end.1.222]
  br label %case.end.1.204
case.end.1.204:
  br label %case.join.194
case.default.193:
  unreachable
case.join.194:
  %t455 = phi ptr [%t199, %case.end.0.196], [%t454, %case.end.1.204]
  br label %case.end.1.186
case.end.1.186:
  br label %case.join.176
case.default.175:
  unreachable
case.join.176:
  %t456 = phi ptr [%t181, %case.end.0.178], [%t455, %case.end.1.186]
  br label %case.end.1.168
case.end.1.168:
  br label %case.join.158
case.default.157:
  unreachable
case.join.158:
  %t457 = phi ptr [%t163, %case.end.0.160], [%t456, %case.end.1.168]
  br label %case.end.1.149
case.end.1.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t458 = phi ptr [%t144, %case.end.0.141], [%t457, %case.end.1.149]
  br label %case.end.1.130
case.end.1.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t459 = phi ptr [%t125, %case.end.0.122], [%t458, %case.end.1.130]
  br label %case.end.1.111
case.end.1.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t460 = phi ptr [%t106, %case.end.0.103], [%t459, %case.end.1.111]
  br label %case.end.1.92
case.end.1.92:
  br label %case.join.82
case.default.81:
  unreachable
case.join.82:
  %t461 = phi ptr [%t87, %case.end.0.84], [%t460, %case.end.1.92]
  br label %case.end.1.73
case.end.1.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t462 = phi ptr [%t68, %case.end.0.65], [%t461, %case.end.1.73]
  br label %case.end.1.54
case.end.1.54:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t463 = phi ptr [%t49, %case.end.0.46], [%t462, %case.end.1.54]
  br label %case.end.1.35
case.end.1.35:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t464 = phi ptr [%t30, %case.end.0.27], [%t463, %case.end.1.35]
  br label %case.end.1.16
case.end.1.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t465 = phi ptr [%t11, %case.end.0.8], [%t464, %case.end.1.16]
  %t466 = call ptr @v__let_7(ptr %t465)
  ret ptr %t466
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
  store ptr @.str.12, ptr %t12
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
