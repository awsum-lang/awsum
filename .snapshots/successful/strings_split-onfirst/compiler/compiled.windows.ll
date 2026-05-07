; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare ptr @strstr(ptr, ptr)
declare ptr @memcpy(ptr, ptr, i64)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [8 x i8] c"Nothing\00"
@.str.1 = private unnamed_addr constant [6 x i8] c"Just(\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"|\00"
@.str.3 = private unnamed_addr constant [2 x i8] c")\00"
@.str.4 = private unnamed_addr constant [2 x i8] c",\00"
@.str.5 = private unnamed_addr constant [6 x i8] c"a,b,c\00"
@.str.6 = private unnamed_addr constant [3 x i8] c"::\00"
@.str.7 = private unnamed_addr constant [16 x i8] c"user::42::admin\00"
@.str.8 = private unnamed_addr constant [2 x i8] c"x\00"
@.str.9 = private unnamed_addr constant [4 x i8] c"abc\00"
@.str.10 = private unnamed_addr constant [1 x i8] c"\00"
@.str.11 = private unnamed_addr constant [2 x i8] c":\00"
@.str.12 = private unnamed_addr constant [5 x i8] c":foo\00"
@.str.13 = private unnamed_addr constant [5 x i8] c"foo:\00"
@.str.14 = private unnamed_addr constant [6 x i8] c"abcde\00"
@.str.15 = private unnamed_addr constant [3 x i8] c"ab\00"
@.str.16 = private unnamed_addr constant [3 x i8] c", \00"
@.str.17 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

define internal ptr @__concat(ptr %a, ptr %b) {
  %la_box = call ptr @__lengthUtf16CodeUnits(ptr %a)
  %la = load i32, ptr %la_box
  %lb_box = call ptr @__lengthUtf16CodeUnits(ptr %b)
  %lb = load i32, ptr %lb_box
  %la64 = zext i32 %la to i64
  %lb64 = zext i32 %lb to i64
  %sum64 = add i64 %la64, %lb64
  %over = icmp ugt i64 %sum64, 134217728
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
  %ba = call i64 @strlen(ptr %a)
  %bb = call i64 @strlen(ptr %b)
  %bsum = add i64 %ba, %bb
  %total = add i64 %bsum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  ret ptr %right
}


define internal ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @__splitOnFirst(ptr %sep, ptr %str) {
  %pos = call ptr @strstr(ptr %str, ptr %sep)
  %is_null = icmp eq ptr %pos, null
  br i1 %is_null, label %not_found, label %found
not_found:
  %nothing = call ptr @malloc(i64 8)
  %nothing_tag = inttoptr i64 0 to ptr
  store ptr %nothing_tag, ptr %nothing
  ret ptr %nothing
found:
  %str_int = ptrtoint ptr %str to i64
  %pos_int = ptrtoint ptr %pos to i64
  %prefix_len = sub i64 %pos_int, %str_int
  %sep_len = call i64 @strlen(ptr %sep)
  %suffix_start = getelementptr i8, ptr %pos, i64 %sep_len
  %suffix_len = call i64 @strlen(ptr %suffix_start)
  %prefix_total = add i64 %prefix_len, 1
  %prefix = call ptr @malloc(i64 %prefix_total)
  call ptr @memcpy(ptr %prefix, ptr %str, i64 %prefix_len)
  %prefix_term = getelementptr i8, ptr %prefix, i64 %prefix_len
  store i8 0, ptr %prefix_term
  %suffix_total = add i64 %suffix_len, 1
  %suffix = call ptr @malloc(i64 %suffix_total)
  call ptr @memcpy(ptr %suffix, ptr %suffix_start, i64 %suffix_len)
  %suffix_term = getelementptr i8, ptr %suffix, i64 %suffix_len
  store i8 0, ptr %suffix_term
  %tuple = call ptr @malloc(i64 24)
  %tuple_tag = inttoptr i64 0 to ptr
  store ptr %tuple_tag, ptr %tuple
  %tuple_a = getelementptr ptr, ptr %tuple, i32 1
  store ptr %prefix, ptr %tuple_a
  %tuple_b = getelementptr ptr, ptr %tuple, i32 2
  store ptr %suffix, ptr %tuple_b
  %just = call ptr @malloc(i64 16)
  %just_tag = inttoptr i64 1 to ptr
  store ptr %just_tag, ptr %just
  %just_f = getelementptr ptr, ptr %just, i32 1
  store ptr %tuple, ptr %just_f
  ret ptr %just
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %bp = getelementptr i8, ptr %s, i64 %i
  %b = load i8, ptr %bp
  %is_nul = icmp eq i8 %b, 0
  br i1 %is_nul, label %done, label %body
body:
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %check4
check4:
  %top5 = and i32 %bz, 248
  %is_4 = icmp eq i32 %top5, 240
  br i1 %is_4, label %add2, label %add1
add2:
  %n2_0 = load i32, ptr %n_p
  %n2_1 = add i32 %n2_0, 2
  store i32 %n2_1, ptr %n_p
  br label %step
add1:
  %n1_0 = load i32, ptr %n_p
  %n1_1 = add i32 %n1_0, 1
  store i32 %n1_1, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
done:
  %nf = load i32, ptr %n_p
  %box = call ptr @malloc(i64 4)
  store i32 %nf, ptr %box
  ret ptr %box
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
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 16)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr [8 x i8], ptr @.str.0, i64 0, i64 0
  %t11 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t11
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_r, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 0, label %case.arm.0.21 ]
case.arm.0.21:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = getelementptr ptr, ptr %t15, i32 2
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @v_renderTuple(ptr %t24, ptr %t26)
  br label %case.end.0.22
case.end.0.22:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t28 = phi ptr [%t27, %case.end.0.22]
  br label %case.end.1.13
case.end.1.13:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t29 = phi ptr [%t7, %case.end.0.6], [%t28, %case.end.1.13]
  ret ptr %t29
}

define internal ptr @v_renderTuple(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr [6 x i8], ptr @.str.1, i64 0, i64 0
  %t1 = call ptr @__concat(ptr %t0, ptr %v_a)
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
  %t19 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t20 = call ptr @__concat(ptr %t18, ptr %t19)
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
  %t38 = call ptr @__concat(ptr %t37, ptr %v_b)
  %t39 = getelementptr ptr, ptr %t38, i32 0
  %t40 = load ptr, ptr %t39
  %t41 = ptrtoint ptr %t40 to i64
  switch i64 %t41, label %case.default.42 [ i64 0, label %case.arm.0.44 i64 1, label %case.arm.1.52 ]
case.arm.0.44:
  %t46 = getelementptr ptr, ptr %t38, i32 1
  %t47 = load ptr, ptr %t46
  %t48 = call ptr @malloc(i64 16)
  %t49 = inttoptr i64 0 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t47, ptr %t51
  br label %case.end.0.45
case.end.0.45:
  br label %case.join.43
case.arm.1.52:
  %t54 = getelementptr ptr, ptr %t38, i32 1
  %t55 = load ptr, ptr %t54
  %t56 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t57 = call ptr @__concat(ptr %t55, ptr %t56)
  br label %case.end.1.53
case.end.1.53:
  br label %case.join.43
case.default.42:
  unreachable
case.join.43:
  %t58 = phi ptr [%t48, %case.end.0.45], [%t57, %case.end.1.53]
  br label %case.end.1.35
case.end.1.35:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t59 = phi ptr [%t30, %case.end.0.27], [%t58, %case.end.1.35]
  br label %case.end.1.16
case.end.1.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t60 = phi ptr [%t11, %case.end.0.8], [%t59, %case.end.1.16]
  ret ptr %t60
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t1 = getelementptr [6 x i8], ptr @.str.5, i64 0, i64 0
  %t2 = call ptr @__splitOnFirst(ptr %t0, ptr %t1)
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
  %t21 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t22 = getelementptr [16 x i8], ptr @.str.7, i64 0, i64 0
  %t23 = call ptr @__splitOnFirst(ptr %t21, ptr %t22)
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
  %t42 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t43 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t44 = call ptr @__splitOnFirst(ptr %t42, ptr %t43)
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
  %t63 = getelementptr [1 x i8], ptr @.str.10, i64 0, i64 0
  %t64 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t65 = call ptr @__splitOnFirst(ptr %t63, ptr %t64)
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
  %t84 = getelementptr [2 x i8], ptr @.str.11, i64 0, i64 0
  %t85 = getelementptr [5 x i8], ptr @.str.12, i64 0, i64 0
  %t86 = call ptr @__splitOnFirst(ptr %t84, ptr %t85)
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
  %t105 = getelementptr [2 x i8], ptr @.str.11, i64 0, i64 0
  %t106 = getelementptr [5 x i8], ptr @.str.13, i64 0, i64 0
  %t107 = call ptr @__splitOnFirst(ptr %t105, ptr %t106)
  %t108 = call ptr @v_render(ptr %t107)
  %t109 = getelementptr ptr, ptr %t108, i32 0
  %t110 = load ptr, ptr %t109
  %t111 = ptrtoint ptr %t110 to i64
  switch i64 %t111, label %case.default.112 [ i64 0, label %case.arm.0.114 i64 1, label %case.arm.1.122 ]
case.arm.0.114:
  %t116 = getelementptr ptr, ptr %t108, i32 1
  %t117 = load ptr, ptr %t116
  %t118 = call ptr @malloc(i64 16)
  %t119 = inttoptr i64 0 to ptr
  %t120 = getelementptr ptr, ptr %t118, i32 0
  store ptr %t119, ptr %t120
  %t121 = getelementptr ptr, ptr %t118, i32 1
  store ptr %t117, ptr %t121
  br label %case.end.0.115
case.end.0.115:
  br label %case.join.113
case.arm.1.122:
  %t124 = getelementptr ptr, ptr %t108, i32 1
  %t125 = load ptr, ptr %t124
  %t126 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t127 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t128 = call ptr @__splitOnFirst(ptr %t126, ptr %t127)
  %t129 = call ptr @v_render(ptr %t128)
  %t130 = getelementptr ptr, ptr %t129, i32 0
  %t131 = load ptr, ptr %t130
  %t132 = ptrtoint ptr %t131 to i64
  switch i64 %t132, label %case.default.133 [ i64 0, label %case.arm.0.135 i64 1, label %case.arm.1.143 ]
case.arm.0.135:
  %t137 = getelementptr ptr, ptr %t129, i32 1
  %t138 = load ptr, ptr %t137
  %t139 = call ptr @malloc(i64 16)
  %t140 = inttoptr i64 0 to ptr
  %t141 = getelementptr ptr, ptr %t139, i32 0
  store ptr %t140, ptr %t141
  %t142 = getelementptr ptr, ptr %t139, i32 1
  store ptr %t138, ptr %t142
  br label %case.end.0.136
case.end.0.136:
  br label %case.join.134
case.arm.1.143:
  %t145 = getelementptr ptr, ptr %t129, i32 1
  %t146 = load ptr, ptr %t145
  %t147 = getelementptr [6 x i8], ptr @.str.14, i64 0, i64 0
  %t148 = getelementptr [3 x i8], ptr @.str.15, i64 0, i64 0
  %t149 = call ptr @__splitOnFirst(ptr %t147, ptr %t148)
  %t150 = call ptr @v_render(ptr %t149)
  %t151 = getelementptr ptr, ptr %t150, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 0, label %case.arm.0.156 i64 1, label %case.arm.1.164 ]
case.arm.0.156:
  %t158 = getelementptr ptr, ptr %t150, i32 1
  %t159 = load ptr, ptr %t158
  %t160 = call ptr @malloc(i64 16)
  %t161 = inttoptr i64 0 to ptr
  %t162 = getelementptr ptr, ptr %t160, i32 0
  store ptr %t161, ptr %t162
  %t163 = getelementptr ptr, ptr %t160, i32 1
  store ptr %t159, ptr %t163
  br label %case.end.0.157
case.end.0.157:
  br label %case.join.155
case.arm.1.164:
  %t166 = getelementptr ptr, ptr %t150, i32 1
  %t167 = load ptr, ptr %t166
  %t168 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t169 = call ptr @__concat(ptr %t20, ptr %t168)
  %t170 = getelementptr ptr, ptr %t169, i32 0
  %t171 = load ptr, ptr %t170
  %t172 = ptrtoint ptr %t171 to i64
  switch i64 %t172, label %case.default.173 [ i64 0, label %case.arm.0.175 i64 1, label %case.arm.1.183 ]
case.arm.0.175:
  %t177 = getelementptr ptr, ptr %t169, i32 1
  %t178 = load ptr, ptr %t177
  %t179 = call ptr @malloc(i64 16)
  %t180 = inttoptr i64 0 to ptr
  %t181 = getelementptr ptr, ptr %t179, i32 0
  store ptr %t180, ptr %t181
  %t182 = getelementptr ptr, ptr %t179, i32 1
  store ptr %t178, ptr %t182
  br label %case.end.0.176
case.end.0.176:
  br label %case.join.174
case.arm.1.183:
  %t185 = getelementptr ptr, ptr %t169, i32 1
  %t186 = load ptr, ptr %t185
  %t187 = call ptr @__concat(ptr %t186, ptr %t41)
  %t188 = getelementptr ptr, ptr %t187, i32 0
  %t189 = load ptr, ptr %t188
  %t190 = ptrtoint ptr %t189 to i64
  switch i64 %t190, label %case.default.191 [ i64 0, label %case.arm.0.193 i64 1, label %case.arm.1.201 ]
case.arm.0.193:
  %t195 = getelementptr ptr, ptr %t187, i32 1
  %t196 = load ptr, ptr %t195
  %t197 = call ptr @malloc(i64 16)
  %t198 = inttoptr i64 0 to ptr
  %t199 = getelementptr ptr, ptr %t197, i32 0
  store ptr %t198, ptr %t199
  %t200 = getelementptr ptr, ptr %t197, i32 1
  store ptr %t196, ptr %t200
  br label %case.end.0.194
case.end.0.194:
  br label %case.join.192
case.arm.1.201:
  %t203 = getelementptr ptr, ptr %t187, i32 1
  %t204 = load ptr, ptr %t203
  %t205 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t206 = call ptr @__concat(ptr %t204, ptr %t205)
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
  %t224 = call ptr @__concat(ptr %t223, ptr %t62)
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
  %t242 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t243 = call ptr @__concat(ptr %t241, ptr %t242)
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
  %t261 = call ptr @__concat(ptr %t260, ptr %t83)
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
  %t279 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t280 = call ptr @__concat(ptr %t278, ptr %t279)
  %t281 = getelementptr ptr, ptr %t280, i32 0
  %t282 = load ptr, ptr %t281
  %t283 = ptrtoint ptr %t282 to i64
  switch i64 %t283, label %case.default.284 [ i64 0, label %case.arm.0.286 i64 1, label %case.arm.1.294 ]
case.arm.0.286:
  %t288 = getelementptr ptr, ptr %t280, i32 1
  %t289 = load ptr, ptr %t288
  %t290 = call ptr @malloc(i64 16)
  %t291 = inttoptr i64 0 to ptr
  %t292 = getelementptr ptr, ptr %t290, i32 0
  store ptr %t291, ptr %t292
  %t293 = getelementptr ptr, ptr %t290, i32 1
  store ptr %t289, ptr %t293
  br label %case.end.0.287
case.end.0.287:
  br label %case.join.285
case.arm.1.294:
  %t296 = getelementptr ptr, ptr %t280, i32 1
  %t297 = load ptr, ptr %t296
  %t298 = call ptr @__concat(ptr %t297, ptr %t104)
  %t299 = getelementptr ptr, ptr %t298, i32 0
  %t300 = load ptr, ptr %t299
  %t301 = ptrtoint ptr %t300 to i64
  switch i64 %t301, label %case.default.302 [ i64 0, label %case.arm.0.304 i64 1, label %case.arm.1.312 ]
case.arm.0.304:
  %t306 = getelementptr ptr, ptr %t298, i32 1
  %t307 = load ptr, ptr %t306
  %t308 = call ptr @malloc(i64 16)
  %t309 = inttoptr i64 0 to ptr
  %t310 = getelementptr ptr, ptr %t308, i32 0
  store ptr %t309, ptr %t310
  %t311 = getelementptr ptr, ptr %t308, i32 1
  store ptr %t307, ptr %t311
  br label %case.end.0.305
case.end.0.305:
  br label %case.join.303
case.arm.1.312:
  %t314 = getelementptr ptr, ptr %t298, i32 1
  %t315 = load ptr, ptr %t314
  %t316 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t317 = call ptr @__concat(ptr %t315, ptr %t316)
  %t318 = getelementptr ptr, ptr %t317, i32 0
  %t319 = load ptr, ptr %t318
  %t320 = ptrtoint ptr %t319 to i64
  switch i64 %t320, label %case.default.321 [ i64 0, label %case.arm.0.323 i64 1, label %case.arm.1.331 ]
case.arm.0.323:
  %t325 = getelementptr ptr, ptr %t317, i32 1
  %t326 = load ptr, ptr %t325
  %t327 = call ptr @malloc(i64 16)
  %t328 = inttoptr i64 0 to ptr
  %t329 = getelementptr ptr, ptr %t327, i32 0
  store ptr %t328, ptr %t329
  %t330 = getelementptr ptr, ptr %t327, i32 1
  store ptr %t326, ptr %t330
  br label %case.end.0.324
case.end.0.324:
  br label %case.join.322
case.arm.1.331:
  %t333 = getelementptr ptr, ptr %t317, i32 1
  %t334 = load ptr, ptr %t333
  %t335 = call ptr @__concat(ptr %t334, ptr %t125)
  %t336 = getelementptr ptr, ptr %t335, i32 0
  %t337 = load ptr, ptr %t336
  %t338 = ptrtoint ptr %t337 to i64
  switch i64 %t338, label %case.default.339 [ i64 0, label %case.arm.0.341 i64 1, label %case.arm.1.349 ]
case.arm.0.341:
  %t343 = getelementptr ptr, ptr %t335, i32 1
  %t344 = load ptr, ptr %t343
  %t345 = call ptr @malloc(i64 16)
  %t346 = inttoptr i64 0 to ptr
  %t347 = getelementptr ptr, ptr %t345, i32 0
  store ptr %t346, ptr %t347
  %t348 = getelementptr ptr, ptr %t345, i32 1
  store ptr %t344, ptr %t348
  br label %case.end.0.342
case.end.0.342:
  br label %case.join.340
case.arm.1.349:
  %t351 = getelementptr ptr, ptr %t335, i32 1
  %t352 = load ptr, ptr %t351
  %t353 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t354 = call ptr @__concat(ptr %t352, ptr %t353)
  %t355 = getelementptr ptr, ptr %t354, i32 0
  %t356 = load ptr, ptr %t355
  %t357 = ptrtoint ptr %t356 to i64
  switch i64 %t357, label %case.default.358 [ i64 0, label %case.arm.0.360 i64 1, label %case.arm.1.368 ]
case.arm.0.360:
  %t362 = getelementptr ptr, ptr %t354, i32 1
  %t363 = load ptr, ptr %t362
  %t364 = call ptr @malloc(i64 16)
  %t365 = inttoptr i64 0 to ptr
  %t366 = getelementptr ptr, ptr %t364, i32 0
  store ptr %t365, ptr %t366
  %t367 = getelementptr ptr, ptr %t364, i32 1
  store ptr %t363, ptr %t367
  br label %case.end.0.361
case.end.0.361:
  br label %case.join.359
case.arm.1.368:
  %t370 = getelementptr ptr, ptr %t354, i32 1
  %t371 = load ptr, ptr %t370
  %t372 = call ptr @__concat(ptr %t371, ptr %t146)
  %t373 = getelementptr ptr, ptr %t372, i32 0
  %t374 = load ptr, ptr %t373
  %t375 = ptrtoint ptr %t374 to i64
  switch i64 %t375, label %case.default.376 [ i64 0, label %case.arm.0.378 i64 1, label %case.arm.1.386 ]
case.arm.0.378:
  %t380 = getelementptr ptr, ptr %t372, i32 1
  %t381 = load ptr, ptr %t380
  %t382 = call ptr @malloc(i64 16)
  %t383 = inttoptr i64 0 to ptr
  %t384 = getelementptr ptr, ptr %t382, i32 0
  store ptr %t383, ptr %t384
  %t385 = getelementptr ptr, ptr %t382, i32 1
  store ptr %t381, ptr %t385
  br label %case.end.0.379
case.end.0.379:
  br label %case.join.377
case.arm.1.386:
  %t388 = getelementptr ptr, ptr %t372, i32 1
  %t389 = load ptr, ptr %t388
  %t390 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t391 = call ptr @__concat(ptr %t389, ptr %t390)
  %t392 = getelementptr ptr, ptr %t391, i32 0
  %t393 = load ptr, ptr %t392
  %t394 = ptrtoint ptr %t393 to i64
  switch i64 %t394, label %case.default.395 [ i64 0, label %case.arm.0.397 i64 1, label %case.arm.1.405 ]
case.arm.0.397:
  %t399 = getelementptr ptr, ptr %t391, i32 1
  %t400 = load ptr, ptr %t399
  %t401 = call ptr @malloc(i64 16)
  %t402 = inttoptr i64 0 to ptr
  %t403 = getelementptr ptr, ptr %t401, i32 0
  store ptr %t402, ptr %t403
  %t404 = getelementptr ptr, ptr %t401, i32 1
  store ptr %t400, ptr %t404
  br label %case.end.0.398
case.end.0.398:
  br label %case.join.396
case.arm.1.405:
  %t407 = getelementptr ptr, ptr %t391, i32 1
  %t408 = load ptr, ptr %t407
  %t409 = call ptr @__concat(ptr %t408, ptr %t167)
  br label %case.end.1.406
case.end.1.406:
  br label %case.join.396
case.default.395:
  unreachable
case.join.396:
  %t410 = phi ptr [%t401, %case.end.0.398], [%t409, %case.end.1.406]
  br label %case.end.1.387
case.end.1.387:
  br label %case.join.377
case.default.376:
  unreachable
case.join.377:
  %t411 = phi ptr [%t382, %case.end.0.379], [%t410, %case.end.1.387]
  br label %case.end.1.369
case.end.1.369:
  br label %case.join.359
case.default.358:
  unreachable
case.join.359:
  %t412 = phi ptr [%t364, %case.end.0.361], [%t411, %case.end.1.369]
  br label %case.end.1.350
case.end.1.350:
  br label %case.join.340
case.default.339:
  unreachable
case.join.340:
  %t413 = phi ptr [%t345, %case.end.0.342], [%t412, %case.end.1.350]
  br label %case.end.1.332
case.end.1.332:
  br label %case.join.322
case.default.321:
  unreachable
case.join.322:
  %t414 = phi ptr [%t327, %case.end.0.324], [%t413, %case.end.1.332]
  br label %case.end.1.313
case.end.1.313:
  br label %case.join.303
case.default.302:
  unreachable
case.join.303:
  %t415 = phi ptr [%t308, %case.end.0.305], [%t414, %case.end.1.313]
  br label %case.end.1.295
case.end.1.295:
  br label %case.join.285
case.default.284:
  unreachable
case.join.285:
  %t416 = phi ptr [%t290, %case.end.0.287], [%t415, %case.end.1.295]
  br label %case.end.1.276
case.end.1.276:
  br label %case.join.266
case.default.265:
  unreachable
case.join.266:
  %t417 = phi ptr [%t271, %case.end.0.268], [%t416, %case.end.1.276]
  br label %case.end.1.258
case.end.1.258:
  br label %case.join.248
case.default.247:
  unreachable
case.join.248:
  %t418 = phi ptr [%t253, %case.end.0.250], [%t417, %case.end.1.258]
  br label %case.end.1.239
case.end.1.239:
  br label %case.join.229
case.default.228:
  unreachable
case.join.229:
  %t419 = phi ptr [%t234, %case.end.0.231], [%t418, %case.end.1.239]
  br label %case.end.1.221
case.end.1.221:
  br label %case.join.211
case.default.210:
  unreachable
case.join.211:
  %t420 = phi ptr [%t216, %case.end.0.213], [%t419, %case.end.1.221]
  br label %case.end.1.202
case.end.1.202:
  br label %case.join.192
case.default.191:
  unreachable
case.join.192:
  %t421 = phi ptr [%t197, %case.end.0.194], [%t420, %case.end.1.202]
  br label %case.end.1.184
case.end.1.184:
  br label %case.join.174
case.default.173:
  unreachable
case.join.174:
  %t422 = phi ptr [%t179, %case.end.0.176], [%t421, %case.end.1.184]
  br label %case.end.1.165
case.end.1.165:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t423 = phi ptr [%t160, %case.end.0.157], [%t422, %case.end.1.165]
  br label %case.end.1.144
case.end.1.144:
  br label %case.join.134
case.default.133:
  unreachable
case.join.134:
  %t424 = phi ptr [%t139, %case.end.0.136], [%t423, %case.end.1.144]
  br label %case.end.1.123
case.end.1.123:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t425 = phi ptr [%t118, %case.end.0.115], [%t424, %case.end.1.123]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t426 = phi ptr [%t97, %case.end.0.94], [%t425, %case.end.1.102]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t427 = phi ptr [%t76, %case.end.0.73], [%t426, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t428 = phi ptr [%t55, %case.end.0.52], [%t427, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t429 = phi ptr [%t34, %case.end.0.31], [%t428, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t430 = phi ptr [%t13, %case.end.0.10], [%t429, %case.end.1.18]
  %t431 = call ptr @v__let_2(ptr %t430)
  ret ptr %t431
}

define internal ptr @v__let_2(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.22 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 24)
  %t10 = inttoptr i64 2 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [16 x i8], ptr @.str.17, i64 0, i64 0
  %t13 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t13
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 8)
  %t18 = inttoptr i64 0 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t20
  %t21 = getelementptr ptr, ptr %t9, i32 2
  store ptr %t14, ptr %t21
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.22:
  %t24 = getelementptr ptr, ptr %v_res, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = call ptr @malloc(i64 24)
  %t27 = inttoptr i64 2 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @malloc(i64 8)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t37
  br label %case.end.1.23
case.end.1.23:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t38 = phi ptr [%t9, %case.end.0.6], [%t26, %case.end.1.23]
  ret ptr %t38
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
  %right_box = call ptr @malloc(i64 16)
  %right_tag_ptr = getelementptr ptr, ptr %right_box, i32 0
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right_tag_ptr
  %right_payload_ptr = getelementptr ptr, ptr %right_box, i32 1
  store ptr %input, ptr %right_payload_ptr
  %io = call ptr @v_main(ptr %right_box)
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
