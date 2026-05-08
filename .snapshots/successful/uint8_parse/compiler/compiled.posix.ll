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
@.str.3 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"255" }
@.str.4 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"256" }
@.str.5 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c"-1" }
@.str.6 = private unnamed_addr constant {i32, i32, [0 x i8]} { i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.7 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"abc" }
@.str.8 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c" 5" }
@.str.9 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"12a" }
@.str.10 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c", " }
@.str.11 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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


define internal ptr @__parseUInt8(ptr %s) {
entry:
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i32, align 4
  store i32 0, ptr %acc_alloca
  %len32 = load i32, ptr %s
  %len = zext i32 %len32 to i64
  %payload = getelementptr i8, ptr %s, i64 8
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i32, ptr %acc_alloca
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
  %x10 = mul i32 %acc, 10
  %acc_next = add i32 %x10, %d
  %big = icmp ugt i32 %acc_next, 255
  br i1 %big, label %fail, label %body_end
body_end:
  store i32 %acc_next, ptr %acc_alloca
  %i_next = add i64 %i, 1
  store i64 %i_next, ptr %i_alloca
  br label %loop_head
ok:
  %result_i8 = trunc i32 %acc to i8
  %box = call ptr @malloc(i64 1)
  store i8 %result_i8, ptr %box
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
  %t17 = call ptr @__showUInt8(ptr %t16)
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
  %t0 = call ptr @__parseUInt8(ptr @.str.2)
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
  %t19 = call ptr @__parseUInt8(ptr @.str.3)
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
  %t38 = call ptr @__parseUInt8(ptr @.str.4)
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
  %t57 = call ptr @__parseUInt8(ptr @.str.5)
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
  %t76 = call ptr @__parseUInt8(ptr @.str.6)
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
  %t95 = call ptr @__parseUInt8(ptr @.str.7)
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
  %t114 = call ptr @__parseUInt8(ptr @.str.8)
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
  %t133 = call ptr @__parseUInt8(ptr @.str.9)
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
  %t152 = call ptr @__concat(ptr %t18, ptr @.str.10)
  %t153 = getelementptr ptr, ptr %t152, i32 0
  %t154 = load ptr, ptr %t153
  %t155 = ptrtoint ptr %t154 to i64
  switch i64 %t155, label %case.default.156 [ i64 0, label %case.arm.0.158 i64 1, label %case.arm.1.166 ]
case.arm.0.158:
  %t160 = getelementptr ptr, ptr %t152, i32 1
  %t161 = load ptr, ptr %t160
  %t162 = call ptr @malloc(i64 16)
  %t163 = inttoptr i64 0 to ptr
  %t164 = getelementptr ptr, ptr %t162, i32 0
  store ptr %t163, ptr %t164
  %t165 = getelementptr ptr, ptr %t162, i32 1
  store ptr %t161, ptr %t165
  br label %case.end.0.159
case.end.0.159:
  br label %case.join.157
case.arm.1.166:
  %t168 = getelementptr ptr, ptr %t152, i32 1
  %t169 = load ptr, ptr %t168
  %t170 = call ptr @__concat(ptr %t169, ptr %t37)
  %t171 = getelementptr ptr, ptr %t170, i32 0
  %t172 = load ptr, ptr %t171
  %t173 = ptrtoint ptr %t172 to i64
  switch i64 %t173, label %case.default.174 [ i64 0, label %case.arm.0.176 i64 1, label %case.arm.1.184 ]
case.arm.0.176:
  %t178 = getelementptr ptr, ptr %t170, i32 1
  %t179 = load ptr, ptr %t178
  %t180 = call ptr @malloc(i64 16)
  %t181 = inttoptr i64 0 to ptr
  %t182 = getelementptr ptr, ptr %t180, i32 0
  store ptr %t181, ptr %t182
  %t183 = getelementptr ptr, ptr %t180, i32 1
  store ptr %t179, ptr %t183
  br label %case.end.0.177
case.end.0.177:
  br label %case.join.175
case.arm.1.184:
  %t186 = getelementptr ptr, ptr %t170, i32 1
  %t187 = load ptr, ptr %t186
  %t188 = call ptr @__concat(ptr %t187, ptr @.str.10)
  %t189 = getelementptr ptr, ptr %t188, i32 0
  %t190 = load ptr, ptr %t189
  %t191 = ptrtoint ptr %t190 to i64
  switch i64 %t191, label %case.default.192 [ i64 0, label %case.arm.0.194 i64 1, label %case.arm.1.202 ]
case.arm.0.194:
  %t196 = getelementptr ptr, ptr %t188, i32 1
  %t197 = load ptr, ptr %t196
  %t198 = call ptr @malloc(i64 16)
  %t199 = inttoptr i64 0 to ptr
  %t200 = getelementptr ptr, ptr %t198, i32 0
  store ptr %t199, ptr %t200
  %t201 = getelementptr ptr, ptr %t198, i32 1
  store ptr %t197, ptr %t201
  br label %case.end.0.195
case.end.0.195:
  br label %case.join.193
case.arm.1.202:
  %t204 = getelementptr ptr, ptr %t188, i32 1
  %t205 = load ptr, ptr %t204
  %t206 = call ptr @__concat(ptr %t205, ptr %t56)
  %t207 = getelementptr ptr, ptr %t206, i32 0
  %t208 = load ptr, ptr %t207
  %t209 = ptrtoint ptr %t208 to i64
  switch i64 %t209, label %case.default.210 [ i64 0, label %case.arm.0.212 i64 1, label %case.arm.1.220 ]
case.arm.0.212:
  %t214 = getelementptr ptr, ptr %t206, i32 1
  %t215 = load ptr, ptr %t214
  %t216 = call ptr @malloc(i64 16)
  %t217 = inttoptr i64 0 to ptr
  %t218 = getelementptr ptr, ptr %t216, i32 0
  store ptr %t217, ptr %t218
  %t219 = getelementptr ptr, ptr %t216, i32 1
  store ptr %t215, ptr %t219
  br label %case.end.0.213
case.end.0.213:
  br label %case.join.211
case.arm.1.220:
  %t222 = getelementptr ptr, ptr %t206, i32 1
  %t223 = load ptr, ptr %t222
  %t224 = call ptr @__concat(ptr %t223, ptr @.str.10)
  %t225 = getelementptr ptr, ptr %t224, i32 0
  %t226 = load ptr, ptr %t225
  %t227 = ptrtoint ptr %t226 to i64
  switch i64 %t227, label %case.default.228 [ i64 0, label %case.arm.0.230 i64 1, label %case.arm.1.238 ]
case.arm.0.230:
  %t232 = getelementptr ptr, ptr %t224, i32 1
  %t233 = load ptr, ptr %t232
  %t234 = call ptr @malloc(i64 16)
  %t235 = inttoptr i64 0 to ptr
  %t236 = getelementptr ptr, ptr %t234, i32 0
  store ptr %t235, ptr %t236
  %t237 = getelementptr ptr, ptr %t234, i32 1
  store ptr %t233, ptr %t237
  br label %case.end.0.231
case.end.0.231:
  br label %case.join.229
case.arm.1.238:
  %t240 = getelementptr ptr, ptr %t224, i32 1
  %t241 = load ptr, ptr %t240
  %t242 = call ptr @__concat(ptr %t241, ptr %t75)
  %t243 = getelementptr ptr, ptr %t242, i32 0
  %t244 = load ptr, ptr %t243
  %t245 = ptrtoint ptr %t244 to i64
  switch i64 %t245, label %case.default.246 [ i64 0, label %case.arm.0.248 i64 1, label %case.arm.1.256 ]
case.arm.0.248:
  %t250 = getelementptr ptr, ptr %t242, i32 1
  %t251 = load ptr, ptr %t250
  %t252 = call ptr @malloc(i64 16)
  %t253 = inttoptr i64 0 to ptr
  %t254 = getelementptr ptr, ptr %t252, i32 0
  store ptr %t253, ptr %t254
  %t255 = getelementptr ptr, ptr %t252, i32 1
  store ptr %t251, ptr %t255
  br label %case.end.0.249
case.end.0.249:
  br label %case.join.247
case.arm.1.256:
  %t258 = getelementptr ptr, ptr %t242, i32 1
  %t259 = load ptr, ptr %t258
  %t260 = call ptr @__concat(ptr %t259, ptr @.str.10)
  %t261 = getelementptr ptr, ptr %t260, i32 0
  %t262 = load ptr, ptr %t261
  %t263 = ptrtoint ptr %t262 to i64
  switch i64 %t263, label %case.default.264 [ i64 0, label %case.arm.0.266 i64 1, label %case.arm.1.274 ]
case.arm.0.266:
  %t268 = getelementptr ptr, ptr %t260, i32 1
  %t269 = load ptr, ptr %t268
  %t270 = call ptr @malloc(i64 16)
  %t271 = inttoptr i64 0 to ptr
  %t272 = getelementptr ptr, ptr %t270, i32 0
  store ptr %t271, ptr %t272
  %t273 = getelementptr ptr, ptr %t270, i32 1
  store ptr %t269, ptr %t273
  br label %case.end.0.267
case.end.0.267:
  br label %case.join.265
case.arm.1.274:
  %t276 = getelementptr ptr, ptr %t260, i32 1
  %t277 = load ptr, ptr %t276
  %t278 = call ptr @__concat(ptr %t277, ptr %t94)
  %t279 = getelementptr ptr, ptr %t278, i32 0
  %t280 = load ptr, ptr %t279
  %t281 = ptrtoint ptr %t280 to i64
  switch i64 %t281, label %case.default.282 [ i64 0, label %case.arm.0.284 i64 1, label %case.arm.1.292 ]
case.arm.0.284:
  %t286 = getelementptr ptr, ptr %t278, i32 1
  %t287 = load ptr, ptr %t286
  %t288 = call ptr @malloc(i64 16)
  %t289 = inttoptr i64 0 to ptr
  %t290 = getelementptr ptr, ptr %t288, i32 0
  store ptr %t289, ptr %t290
  %t291 = getelementptr ptr, ptr %t288, i32 1
  store ptr %t287, ptr %t291
  br label %case.end.0.285
case.end.0.285:
  br label %case.join.283
case.arm.1.292:
  %t294 = getelementptr ptr, ptr %t278, i32 1
  %t295 = load ptr, ptr %t294
  %t296 = call ptr @__concat(ptr %t295, ptr @.str.10)
  %t297 = getelementptr ptr, ptr %t296, i32 0
  %t298 = load ptr, ptr %t297
  %t299 = ptrtoint ptr %t298 to i64
  switch i64 %t299, label %case.default.300 [ i64 0, label %case.arm.0.302 i64 1, label %case.arm.1.310 ]
case.arm.0.302:
  %t304 = getelementptr ptr, ptr %t296, i32 1
  %t305 = load ptr, ptr %t304
  %t306 = call ptr @malloc(i64 16)
  %t307 = inttoptr i64 0 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  %t309 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t305, ptr %t309
  br label %case.end.0.303
case.end.0.303:
  br label %case.join.301
case.arm.1.310:
  %t312 = getelementptr ptr, ptr %t296, i32 1
  %t313 = load ptr, ptr %t312
  %t314 = call ptr @__concat(ptr %t313, ptr %t113)
  %t315 = getelementptr ptr, ptr %t314, i32 0
  %t316 = load ptr, ptr %t315
  %t317 = ptrtoint ptr %t316 to i64
  switch i64 %t317, label %case.default.318 [ i64 0, label %case.arm.0.320 i64 1, label %case.arm.1.328 ]
case.arm.0.320:
  %t322 = getelementptr ptr, ptr %t314, i32 1
  %t323 = load ptr, ptr %t322
  %t324 = call ptr @malloc(i64 16)
  %t325 = inttoptr i64 0 to ptr
  %t326 = getelementptr ptr, ptr %t324, i32 0
  store ptr %t325, ptr %t326
  %t327 = getelementptr ptr, ptr %t324, i32 1
  store ptr %t323, ptr %t327
  br label %case.end.0.321
case.end.0.321:
  br label %case.join.319
case.arm.1.328:
  %t330 = getelementptr ptr, ptr %t314, i32 1
  %t331 = load ptr, ptr %t330
  %t332 = call ptr @__concat(ptr %t331, ptr @.str.10)
  %t333 = getelementptr ptr, ptr %t332, i32 0
  %t334 = load ptr, ptr %t333
  %t335 = ptrtoint ptr %t334 to i64
  switch i64 %t335, label %case.default.336 [ i64 0, label %case.arm.0.338 i64 1, label %case.arm.1.346 ]
case.arm.0.338:
  %t340 = getelementptr ptr, ptr %t332, i32 1
  %t341 = load ptr, ptr %t340
  %t342 = call ptr @malloc(i64 16)
  %t343 = inttoptr i64 0 to ptr
  %t344 = getelementptr ptr, ptr %t342, i32 0
  store ptr %t343, ptr %t344
  %t345 = getelementptr ptr, ptr %t342, i32 1
  store ptr %t341, ptr %t345
  br label %case.end.0.339
case.end.0.339:
  br label %case.join.337
case.arm.1.346:
  %t348 = getelementptr ptr, ptr %t332, i32 1
  %t349 = load ptr, ptr %t348
  %t350 = call ptr @__concat(ptr %t349, ptr %t132)
  %t351 = getelementptr ptr, ptr %t350, i32 0
  %t352 = load ptr, ptr %t351
  %t353 = ptrtoint ptr %t352 to i64
  switch i64 %t353, label %case.default.354 [ i64 0, label %case.arm.0.356 i64 1, label %case.arm.1.364 ]
case.arm.0.356:
  %t358 = getelementptr ptr, ptr %t350, i32 1
  %t359 = load ptr, ptr %t358
  %t360 = call ptr @malloc(i64 16)
  %t361 = inttoptr i64 0 to ptr
  %t362 = getelementptr ptr, ptr %t360, i32 0
  store ptr %t361, ptr %t362
  %t363 = getelementptr ptr, ptr %t360, i32 1
  store ptr %t359, ptr %t363
  br label %case.end.0.357
case.end.0.357:
  br label %case.join.355
case.arm.1.364:
  %t366 = getelementptr ptr, ptr %t350, i32 1
  %t367 = load ptr, ptr %t366
  %t368 = call ptr @__concat(ptr %t367, ptr @.str.10)
  %t369 = getelementptr ptr, ptr %t368, i32 0
  %t370 = load ptr, ptr %t369
  %t371 = ptrtoint ptr %t370 to i64
  switch i64 %t371, label %case.default.372 [ i64 0, label %case.arm.0.374 i64 1, label %case.arm.1.382 ]
case.arm.0.374:
  %t376 = getelementptr ptr, ptr %t368, i32 1
  %t377 = load ptr, ptr %t376
  %t378 = call ptr @malloc(i64 16)
  %t379 = inttoptr i64 0 to ptr
  %t380 = getelementptr ptr, ptr %t378, i32 0
  store ptr %t379, ptr %t380
  %t381 = getelementptr ptr, ptr %t378, i32 1
  store ptr %t377, ptr %t381
  br label %case.end.0.375
case.end.0.375:
  br label %case.join.373
case.arm.1.382:
  %t384 = getelementptr ptr, ptr %t368, i32 1
  %t385 = load ptr, ptr %t384
  %t386 = call ptr @__concat(ptr %t385, ptr %t151)
  br label %case.end.1.383
case.end.1.383:
  br label %case.join.373
case.default.372:
  unreachable
case.join.373:
  %t387 = phi ptr [%t378, %case.end.0.375], [%t386, %case.end.1.383]
  br label %case.end.1.365
case.end.1.365:
  br label %case.join.355
case.default.354:
  unreachable
case.join.355:
  %t388 = phi ptr [%t360, %case.end.0.357], [%t387, %case.end.1.365]
  br label %case.end.1.347
case.end.1.347:
  br label %case.join.337
case.default.336:
  unreachable
case.join.337:
  %t389 = phi ptr [%t342, %case.end.0.339], [%t388, %case.end.1.347]
  br label %case.end.1.329
case.end.1.329:
  br label %case.join.319
case.default.318:
  unreachable
case.join.319:
  %t390 = phi ptr [%t324, %case.end.0.321], [%t389, %case.end.1.329]
  br label %case.end.1.311
case.end.1.311:
  br label %case.join.301
case.default.300:
  unreachable
case.join.301:
  %t391 = phi ptr [%t306, %case.end.0.303], [%t390, %case.end.1.311]
  br label %case.end.1.293
case.end.1.293:
  br label %case.join.283
case.default.282:
  unreachable
case.join.283:
  %t392 = phi ptr [%t288, %case.end.0.285], [%t391, %case.end.1.293]
  br label %case.end.1.275
case.end.1.275:
  br label %case.join.265
case.default.264:
  unreachable
case.join.265:
  %t393 = phi ptr [%t270, %case.end.0.267], [%t392, %case.end.1.275]
  br label %case.end.1.257
case.end.1.257:
  br label %case.join.247
case.default.246:
  unreachable
case.join.247:
  %t394 = phi ptr [%t252, %case.end.0.249], [%t393, %case.end.1.257]
  br label %case.end.1.239
case.end.1.239:
  br label %case.join.229
case.default.228:
  unreachable
case.join.229:
  %t395 = phi ptr [%t234, %case.end.0.231], [%t394, %case.end.1.239]
  br label %case.end.1.221
case.end.1.221:
  br label %case.join.211
case.default.210:
  unreachable
case.join.211:
  %t396 = phi ptr [%t216, %case.end.0.213], [%t395, %case.end.1.221]
  br label %case.end.1.203
case.end.1.203:
  br label %case.join.193
case.default.192:
  unreachable
case.join.193:
  %t397 = phi ptr [%t198, %case.end.0.195], [%t396, %case.end.1.203]
  br label %case.end.1.185
case.end.1.185:
  br label %case.join.175
case.default.174:
  unreachable
case.join.175:
  %t398 = phi ptr [%t180, %case.end.0.177], [%t397, %case.end.1.185]
  br label %case.end.1.167
case.end.1.167:
  br label %case.join.157
case.default.156:
  unreachable
case.join.157:
  %t399 = phi ptr [%t162, %case.end.0.159], [%t398, %case.end.1.167]
  br label %case.end.1.149
case.end.1.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t400 = phi ptr [%t144, %case.end.0.141], [%t399, %case.end.1.149]
  br label %case.end.1.130
case.end.1.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t401 = phi ptr [%t125, %case.end.0.122], [%t400, %case.end.1.130]
  br label %case.end.1.111
case.end.1.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t402 = phi ptr [%t106, %case.end.0.103], [%t401, %case.end.1.111]
  br label %case.end.1.92
case.end.1.92:
  br label %case.join.82
case.default.81:
  unreachable
case.join.82:
  %t403 = phi ptr [%t87, %case.end.0.84], [%t402, %case.end.1.92]
  br label %case.end.1.73
case.end.1.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t404 = phi ptr [%t68, %case.end.0.65], [%t403, %case.end.1.73]
  br label %case.end.1.54
case.end.1.54:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t405 = phi ptr [%t49, %case.end.0.46], [%t404, %case.end.1.54]
  br label %case.end.1.35
case.end.1.35:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t406 = phi ptr [%t30, %case.end.0.27], [%t405, %case.end.1.35]
  br label %case.end.1.16
case.end.1.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t407 = phi ptr [%t11, %case.end.0.8], [%t406, %case.end.1.16]
  %t408 = call ptr @v__let_7(ptr %t407)
  ret ptr %t408
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
  store ptr @.str.11, ptr %t12
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
