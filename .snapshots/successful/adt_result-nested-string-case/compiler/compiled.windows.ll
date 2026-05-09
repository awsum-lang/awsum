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
  switch i64 %t2, label %case.default.3 [ i64 19, label %case.arm.19.5 i64 20, label %case.arm.20.23 ]
case.arm.19.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 19, label %case.arm.19.14 i64 20, label %case.arm.20.18 ]
case.arm.19.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  br label %case.end.19.15
case.end.19.15:
  br label %case.join.13
case.arm.20.18:
  %t20 = getelementptr ptr, ptr %t8, i32 1
  %t21 = load ptr, ptr %t20
  br label %case.end.20.19
case.end.20.19:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t22 = phi ptr [%t17, %case.end.19.15], [%t21, %case.end.20.19]
  br label %case.end.19.6
case.end.19.6:
  br label %case.join.4
case.arm.20.23:
  %t25 = getelementptr ptr, ptr %v_r, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 19, label %case.arm.19.32 i64 20, label %case.arm.20.36 ]
case.arm.19.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  br label %case.end.19.33
case.end.19.33:
  br label %case.join.31
case.arm.20.36:
  %t38 = getelementptr ptr, ptr %t26, i32 1
  %t39 = load ptr, ptr %t38
  br label %case.end.20.37
case.end.20.37:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t40 = phi ptr [%t35, %case.end.19.33], [%t39, %case.end.20.37]
  br label %case.end.20.24
case.end.20.24:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t41 = phi ptr [%t22, %case.end.19.6], [%t40, %case.end.20.24]
  ret ptr %t41
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
  %t6 = getelementptr ptr, ptr %t3, i32 1
  store ptr @.str.0, ptr %t6
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t7
  %t8 = call ptr @v_unwrap(ptr %t0)
  %t9 = call ptr @__concat(ptr %t8, ptr @.str.1)
  %t10 = getelementptr ptr, ptr %t9, i32 0
  %t11 = load ptr, ptr %t10
  %t12 = ptrtoint ptr %t11 to i64
  switch i64 %t12, label %case.default.13 [ i64 3, label %case.arm.3.15 i64 4, label %case.arm.4.23 ]
case.arm.3.15:
  %t17 = getelementptr ptr, ptr %t9, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 3 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t18, ptr %t22
  br label %case.end.3.16
case.end.3.16:
  br label %case.join.14
case.arm.4.23:
  %t25 = getelementptr ptr, ptr %t9, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 16)
  %t28 = inttoptr i64 19 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 20 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr @.str.2, ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  %t35 = call ptr @v_unwrap(ptr %t27)
  %t36 = call ptr @__concat(ptr %t26, ptr %t35)
  %t37 = getelementptr ptr, ptr %t36, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 3, label %case.arm.3.42 i64 4, label %case.arm.4.50 ]
case.arm.3.42:
  %t44 = getelementptr ptr, ptr %t36, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t45, ptr %t49
  br label %case.end.3.43
case.end.3.43:
  br label %case.join.41
case.arm.4.50:
  %t52 = getelementptr ptr, ptr %t36, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = call ptr @__concat(ptr %t53, ptr @.str.1)
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 3, label %case.arm.3.60 i64 4, label %case.arm.4.68 ]
case.arm.3.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = call ptr @malloc(i64 16)
  %t65 = inttoptr i64 3 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t63, ptr %t67
  br label %case.end.3.61
case.end.3.61:
  br label %case.join.59
case.arm.4.68:
  %t70 = getelementptr ptr, ptr %t54, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 20 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = call ptr @malloc(i64 16)
  %t76 = inttoptr i64 19 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr @.str.3, ptr %t78
  %t79 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t75, ptr %t79
  %t80 = call ptr @v_unwrap(ptr %t72)
  %t81 = call ptr @__concat(ptr %t71, ptr %t80)
  %t82 = getelementptr ptr, ptr %t81, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 3, label %case.arm.3.87 i64 4, label %case.arm.4.95 ]
case.arm.3.87:
  %t89 = getelementptr ptr, ptr %t81, i32 1
  %t90 = load ptr, ptr %t89
  %t91 = call ptr @malloc(i64 16)
  %t92 = inttoptr i64 3 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  %t94 = getelementptr ptr, ptr %t91, i32 1
  store ptr %t90, ptr %t94
  br label %case.end.3.88
case.end.3.88:
  br label %case.join.86
case.arm.4.95:
  %t97 = getelementptr ptr, ptr %t81, i32 1
  %t98 = load ptr, ptr %t97
  %t99 = call ptr @__concat(ptr %t98, ptr @.str.1)
  %t100 = getelementptr ptr, ptr %t99, i32 0
  %t101 = load ptr, ptr %t100
  %t102 = ptrtoint ptr %t101 to i64
  switch i64 %t102, label %case.default.103 [ i64 3, label %case.arm.3.105 i64 4, label %case.arm.4.113 ]
case.arm.3.105:
  %t107 = getelementptr ptr, ptr %t99, i32 1
  %t108 = load ptr, ptr %t107
  %t109 = call ptr @malloc(i64 16)
  %t110 = inttoptr i64 3 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  %t112 = getelementptr ptr, ptr %t109, i32 1
  store ptr %t108, ptr %t112
  br label %case.end.3.106
case.end.3.106:
  br label %case.join.104
case.arm.4.113:
  %t115 = getelementptr ptr, ptr %t99, i32 1
  %t116 = load ptr, ptr %t115
  %t117 = call ptr @malloc(i64 16)
  %t118 = inttoptr i64 20 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  %t120 = call ptr @malloc(i64 16)
  %t121 = inttoptr i64 20 to ptr
  %t122 = getelementptr ptr, ptr %t120, i32 0
  store ptr %t121, ptr %t122
  %t123 = getelementptr ptr, ptr %t120, i32 1
  store ptr @.str.4, ptr %t123
  %t124 = getelementptr ptr, ptr %t117, i32 1
  store ptr %t120, ptr %t124
  %t125 = call ptr @v_unwrap(ptr %t117)
  %t126 = call ptr @__concat(ptr %t116, ptr %t125)
  br label %case.end.4.114
case.end.4.114:
  br label %case.join.104
case.default.103:
  unreachable
case.join.104:
  %t127 = phi ptr [%t109, %case.end.3.106], [%t126, %case.end.4.114]
  br label %case.end.4.96
case.end.4.96:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t128 = phi ptr [%t91, %case.end.3.88], [%t127, %case.end.4.96]
  br label %case.end.4.69
case.end.4.69:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t129 = phi ptr [%t64, %case.end.3.61], [%t128, %case.end.4.69]
  br label %case.end.4.51
case.end.4.51:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t130 = phi ptr [%t46, %case.end.3.43], [%t129, %case.end.4.51]
  br label %case.end.4.24
case.end.4.24:
  br label %case.join.14
case.default.13:
  unreachable
case.join.14:
  %t131 = phi ptr [%t19, %case.end.3.16], [%t130, %case.end.4.24]
  %t132 = call ptr @v__let_7(ptr %t131)
  ret ptr %t132
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
  store ptr @.str.5, ptr %t12
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
