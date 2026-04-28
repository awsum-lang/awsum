; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [2 x i8] c"1\00"
@.str.1 = private unnamed_addr constant [2 x i8] c",\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"2\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"3\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"4\00"
@.str.5 = private unnamed_addr constant [2 x i8] c"5\00"
@.str.6 = private unnamed_addr constant [2 x i8] c"6\00"
@.str.7 = private unnamed_addr constant [2 x i8] c"7\00"
@.str.8 = private unnamed_addr constant [2 x i8] c"8\00"

define internal ptr @__concat(ptr %a, ptr %b) {
  %la = call i64 @strlen(ptr %a)
  %lb = call i64 @strlen(ptr %b)
  %sum = add i64 %la, %lb
  %total = add i64 %sum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  ret ptr %buf
}


define internal ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  ret ptr null
}


define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.51 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.32 ]
case.arm.0.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 0, label %case.arm.0.23 i64 1, label %case.arm.1.27 ]
case.arm.0.23:
  %t25 = getelementptr ptr, ptr %t17, i32 1
  %t26 = load ptr, ptr %t25
  br label %case.end.0.24
case.end.0.24:
  br label %case.join.22
case.arm.1.27:
  %t29 = getelementptr ptr, ptr %t17, i32 1
  %t30 = load ptr, ptr %t29
  br label %case.end.1.28
case.end.1.28:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t31 = phi ptr [%t26, %case.end.0.24], [%t30, %case.end.1.28]
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.32:
  %t34 = getelementptr ptr, ptr %t8, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = getelementptr ptr, ptr %t35, i32 0
  %t37 = load ptr, ptr %t36
  %t38 = ptrtoint ptr %t37 to i64
  switch i64 %t38, label %case.default.39 [ i64 0, label %case.arm.0.41 i64 1, label %case.arm.1.45 ]
case.arm.0.41:
  %t43 = getelementptr ptr, ptr %t35, i32 1
  %t44 = load ptr, ptr %t43
  br label %case.end.0.42
case.end.0.42:
  br label %case.join.40
case.arm.1.45:
  %t47 = getelementptr ptr, ptr %t35, i32 1
  %t48 = load ptr, ptr %t47
  br label %case.end.1.46
case.end.1.46:
  br label %case.join.40
case.default.39:
  unreachable
case.join.40:
  %t49 = phi ptr [%t44, %case.end.0.42], [%t48, %case.end.1.46]
  br label %case.end.1.33
case.end.1.33:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t50 = phi ptr [%t31, %case.end.0.15], [%t49, %case.end.1.33]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.51:
  %t53 = getelementptr ptr, ptr %v_r, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 0, label %case.arm.0.60 i64 1, label %case.arm.1.78 ]
case.arm.0.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = getelementptr ptr, ptr %t63, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 0, label %case.arm.0.69 i64 1, label %case.arm.1.73 ]
case.arm.0.69:
  %t71 = getelementptr ptr, ptr %t63, i32 1
  %t72 = load ptr, ptr %t71
  br label %case.end.0.70
case.end.0.70:
  br label %case.join.68
case.arm.1.73:
  %t75 = getelementptr ptr, ptr %t63, i32 1
  %t76 = load ptr, ptr %t75
  br label %case.end.1.74
case.end.1.74:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t77 = phi ptr [%t72, %case.end.0.70], [%t76, %case.end.1.74]
  br label %case.end.0.61
case.end.0.61:
  br label %case.join.59
case.arm.1.78:
  %t80 = getelementptr ptr, ptr %t54, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t81, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 0, label %case.arm.0.87 i64 1, label %case.arm.1.91 ]
case.arm.0.87:
  %t89 = getelementptr ptr, ptr %t81, i32 1
  %t90 = load ptr, ptr %t89
  br label %case.end.0.88
case.end.0.88:
  br label %case.join.86
case.arm.1.91:
  %t93 = getelementptr ptr, ptr %t81, i32 1
  %t94 = load ptr, ptr %t93
  br label %case.end.1.92
case.end.1.92:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t95 = phi ptr [%t90, %case.end.0.88], [%t94, %case.end.1.92]
  br label %case.end.1.79
case.end.1.79:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t96 = phi ptr [%t77, %case.end.0.61], [%t95, %case.end.1.79]
  br label %case.end.1.52
case.end.1.52:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t97 = phi ptr [%t50, %case.end.0.6], [%t96, %case.end.1.52]
  ret ptr %t97
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 16)
  %t7 = inttoptr i64 0 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t12
  %t13 = call ptr @v_unwrap(ptr %t0)
  %t14 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t15 = call ptr @__concat(ptr %t13, ptr %t14)
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 0 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @malloc(i64 16)
  %t23 = inttoptr i64 1 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t26 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t27
  %t28 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t28
  %t29 = call ptr @v_unwrap(ptr %t16)
  %t30 = call ptr @__concat(ptr %t15, ptr %t29)
  %t31 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t32 = call ptr @__concat(ptr %t30, ptr %t31)
  %t33 = call ptr @malloc(i64 16)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 1 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @malloc(i64 16)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t43 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t44
  %t45 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t45
  %t46 = call ptr @v_unwrap(ptr %t33)
  %t47 = call ptr @__concat(ptr %t32, ptr %t46)
  %t48 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t49 = call ptr @__concat(ptr %t47, ptr %t48)
  %t50 = call ptr @malloc(i64 16)
  %t51 = inttoptr i64 0 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @malloc(i64 16)
  %t54 = inttoptr i64 1 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @malloc(i64 16)
  %t57 = inttoptr i64 1 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t60 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t60
  %t61 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t61
  %t62 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t62
  %t63 = call ptr @v_unwrap(ptr %t50)
  %t64 = call ptr @__concat(ptr %t49, ptr %t63)
  %t65 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t66 = call ptr @__concat(ptr %t64, ptr %t65)
  %t67 = call ptr @malloc(i64 16)
  %t68 = inttoptr i64 1 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @malloc(i64 16)
  %t71 = inttoptr i64 0 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = call ptr @malloc(i64 16)
  %t74 = inttoptr i64 0 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t77 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t73, ptr %t78
  %t79 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t70, ptr %t79
  %t80 = call ptr @v_unwrap(ptr %t67)
  %t81 = call ptr @__concat(ptr %t66, ptr %t80)
  %t82 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t83 = call ptr @__concat(ptr %t81, ptr %t82)
  %t84 = call ptr @malloc(i64 16)
  %t85 = inttoptr i64 1 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = call ptr @malloc(i64 16)
  %t88 = inttoptr i64 0 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  %t90 = call ptr @malloc(i64 16)
  %t91 = inttoptr i64 1 to ptr
  %t92 = getelementptr ptr, ptr %t90, i32 0
  store ptr %t91, ptr %t92
  %t93 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t94 = getelementptr ptr, ptr %t90, i32 1
  store ptr %t93, ptr %t94
  %t95 = getelementptr ptr, ptr %t87, i32 1
  store ptr %t90, ptr %t95
  %t96 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t87, ptr %t96
  %t97 = call ptr @v_unwrap(ptr %t84)
  %t98 = call ptr @__concat(ptr %t83, ptr %t97)
  %t99 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t100 = call ptr @__concat(ptr %t98, ptr %t99)
  %t101 = call ptr @malloc(i64 16)
  %t102 = inttoptr i64 1 to ptr
  %t103 = getelementptr ptr, ptr %t101, i32 0
  store ptr %t102, ptr %t103
  %t104 = call ptr @malloc(i64 16)
  %t105 = inttoptr i64 1 to ptr
  %t106 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t105, ptr %t106
  %t107 = call ptr @malloc(i64 16)
  %t108 = inttoptr i64 0 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = getelementptr [2 x i8], ptr @.str.7, i64 0, i64 0
  %t111 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t110, ptr %t111
  %t112 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t107, ptr %t112
  %t113 = getelementptr ptr, ptr %t101, i32 1
  store ptr %t104, ptr %t113
  %t114 = call ptr @v_unwrap(ptr %t101)
  %t115 = call ptr @__concat(ptr %t100, ptr %t114)
  %t116 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t117 = call ptr @__concat(ptr %t115, ptr %t116)
  %t118 = call ptr @malloc(i64 16)
  %t119 = inttoptr i64 1 to ptr
  %t120 = getelementptr ptr, ptr %t118, i32 0
  store ptr %t119, ptr %t120
  %t121 = call ptr @malloc(i64 16)
  %t122 = inttoptr i64 1 to ptr
  %t123 = getelementptr ptr, ptr %t121, i32 0
  store ptr %t122, ptr %t123
  %t124 = call ptr @malloc(i64 16)
  %t125 = inttoptr i64 1 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t128 = getelementptr ptr, ptr %t124, i32 1
  store ptr %t127, ptr %t128
  %t129 = getelementptr ptr, ptr %t121, i32 1
  store ptr %t124, ptr %t129
  %t130 = getelementptr ptr, ptr %t118, i32 1
  store ptr %t121, ptr %t130
  %t131 = call ptr @v_unwrap(ptr %t118)
  %t132 = call ptr @__concat(ptr %t117, ptr %t131)
  %t133 = call ptr @__print(ptr %t132)
  ret ptr %t133
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
  call ptr @v_main(ptr %input)
  ret i32 0
}
