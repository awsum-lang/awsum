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

@.str.0 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c", " }
@.str.1 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_main() {
  %t0 = call ptr @v_minInt32()
  %t1 = call ptr @__showInt32(ptr %t0)
  %t2 = call ptr @__concat(ptr %t1, ptr @.str.0)
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
  store i32 -42, ptr %t20
  %t21 = call ptr @__showInt32(ptr %t20)
  %t22 = call ptr @__concat(ptr %t19, ptr %t21)
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
  %t40 = call ptr @__concat(ptr %t39, ptr @.str.0)
  %t41 = getelementptr ptr, ptr %t40, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %case.default.44 [ i64 3, label %case.arm.3.46 i64 4, label %case.arm.4.54 ]
case.arm.3.46:
  %t48 = getelementptr ptr, ptr %t40, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = call ptr @malloc(i64 16)
  %t51 = inttoptr i64 3 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t49, ptr %t53
  br label %case.end.3.47
case.end.3.47:
  br label %case.join.45
case.arm.4.54:
  %t56 = getelementptr ptr, ptr %t40, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 4)
  store i32 0, ptr %t58
  %t59 = call ptr @__showInt32(ptr %t58)
  %t60 = call ptr @__concat(ptr %t57, ptr %t59)
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
  %t78 = call ptr @__concat(ptr %t77, ptr @.str.0)
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
  %t96 = call ptr @malloc(i64 4)
  store i32 7, ptr %t96
  %t97 = call ptr @__showInt32(ptr %t96)
  %t98 = call ptr @__concat(ptr %t95, ptr %t97)
  %t99 = getelementptr ptr, ptr %t98, i32 0
  %t100 = load ptr, ptr %t99
  %t101 = ptrtoint ptr %t100 to i64
  switch i64 %t101, label %case.default.102 [ i64 3, label %case.arm.3.104 i64 4, label %case.arm.4.112 ]
case.arm.3.104:
  %t106 = getelementptr ptr, ptr %t98, i32 1
  %t107 = load ptr, ptr %t106
  %t108 = call ptr @malloc(i64 16)
  %t109 = inttoptr i64 3 to ptr
  %t110 = getelementptr ptr, ptr %t108, i32 0
  store ptr %t109, ptr %t110
  %t111 = getelementptr ptr, ptr %t108, i32 1
  store ptr %t107, ptr %t111
  br label %case.end.3.105
case.end.3.105:
  br label %case.join.103
case.arm.4.112:
  %t114 = getelementptr ptr, ptr %t98, i32 1
  %t115 = load ptr, ptr %t114
  %t116 = call ptr @__concat(ptr %t115, ptr @.str.0)
  %t117 = getelementptr ptr, ptr %t116, i32 0
  %t118 = load ptr, ptr %t117
  %t119 = ptrtoint ptr %t118 to i64
  switch i64 %t119, label %case.default.120 [ i64 3, label %case.arm.3.122 i64 4, label %case.arm.4.130 ]
case.arm.3.122:
  %t124 = getelementptr ptr, ptr %t116, i32 1
  %t125 = load ptr, ptr %t124
  %t126 = call ptr @malloc(i64 16)
  %t127 = inttoptr i64 3 to ptr
  %t128 = getelementptr ptr, ptr %t126, i32 0
  store ptr %t127, ptr %t128
  %t129 = getelementptr ptr, ptr %t126, i32 1
  store ptr %t125, ptr %t129
  br label %case.end.3.123
case.end.3.123:
  br label %case.join.121
case.arm.4.130:
  %t132 = getelementptr ptr, ptr %t116, i32 1
  %t133 = load ptr, ptr %t132
  %t134 = call ptr @malloc(i64 4)
  store i32 1234567, ptr %t134
  %t135 = call ptr @__showInt32(ptr %t134)
  %t136 = call ptr @__concat(ptr %t133, ptr %t135)
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
  %t154 = call ptr @__concat(ptr %t153, ptr @.str.0)
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
  %t172 = call ptr @v_maxInt32()
  %t173 = call ptr @__showInt32(ptr %t172)
  %t174 = call ptr @__concat(ptr %t171, ptr %t173)
  br label %case.end.4.169
case.end.4.169:
  br label %case.join.159
case.default.158:
  unreachable
case.join.159:
  %t175 = phi ptr [%t164, %case.end.3.161], [%t174, %case.end.4.169]
  br label %case.end.4.151
case.end.4.151:
  br label %case.join.141
case.default.140:
  unreachable
case.join.141:
  %t176 = phi ptr [%t146, %case.end.3.143], [%t175, %case.end.4.151]
  br label %case.end.4.131
case.end.4.131:
  br label %case.join.121
case.default.120:
  unreachable
case.join.121:
  %t177 = phi ptr [%t126, %case.end.3.123], [%t176, %case.end.4.131]
  br label %case.end.4.113
case.end.4.113:
  br label %case.join.103
case.default.102:
  unreachable
case.join.103:
  %t178 = phi ptr [%t108, %case.end.3.105], [%t177, %case.end.4.113]
  br label %case.end.4.93
case.end.4.93:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t179 = phi ptr [%t88, %case.end.3.85], [%t178, %case.end.4.93]
  br label %case.end.4.75
case.end.4.75:
  br label %case.join.65
case.default.64:
  unreachable
case.join.65:
  %t180 = phi ptr [%t70, %case.end.3.67], [%t179, %case.end.4.75]
  br label %case.end.4.55
case.end.4.55:
  br label %case.join.45
case.default.44:
  unreachable
case.join.45:
  %t181 = phi ptr [%t50, %case.end.3.47], [%t180, %case.end.4.55]
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t182 = phi ptr [%t32, %case.end.3.29], [%t181, %case.end.4.37]
  br label %case.end.4.17
case.end.4.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t183 = phi ptr [%t12, %case.end.3.9], [%t182, %case.end.4.17]
  %t184 = call ptr @v__let_7(ptr %t183)
  ret ptr %t184
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
  store ptr @.str.1, ptr %t12
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
