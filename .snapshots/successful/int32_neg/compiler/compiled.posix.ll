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

@.str.0 = private unnamed_addr constant [14 x i8] c"OverflowError\00"
@.str.1 = private unnamed_addr constant [11 x i8] c"overflow: \00"
@.str.2 = private unnamed_addr constant [5 x i8] c"ok: \00"
@.str.3 = private unnamed_addr constant [3 x i8] c", \00"
@.str.4 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @__negInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
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
  %newv = sub i32 0, %v
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
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

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  %t0 = getelementptr [14 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
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
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [11 x i8], ptr @.str.1, i64 0, i64 0
  %t10 = call ptr @v_showOverflowError(ptr %t8)
  %t11 = call ptr @__concat(ptr %t9, ptr %t10)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_r, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr [5 x i8], ptr @.str.2, i64 0, i64 0
  %t17 = call ptr @__showInt32(ptr %t15)
  %t18 = call ptr @__concat(ptr %t16, ptr %t17)
  br label %case.end.1.13
case.end.1.13:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t19 = phi ptr [%t11, %case.end.0.6], [%t18, %case.end.1.13]
  ret ptr %t19
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 5, ptr %t0
  %t1 = call ptr @__negInt32(ptr %t0)
  %t2 = call ptr @v_render(ptr %t1)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 0, label %case.arm.0.8 i64 1, label %case.arm.1.16 ]
case.arm.0.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  br label %case.end.0.9
case.end.0.9:
  br label %case.join.7
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %t2, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 4)
  store i32 -5, ptr %t20
  %t21 = call ptr @__negInt32(ptr %t20)
  %t22 = call ptr @v_render(ptr %t21)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 0, label %case.arm.0.28 i64 1, label %case.arm.1.36 ]
case.arm.0.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  br label %case.end.0.29
case.end.0.29:
  br label %case.join.27
case.arm.1.36:
  %t38 = getelementptr ptr, ptr %t22, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @malloc(i64 4)
  store i32 0, ptr %t40
  %t41 = call ptr @__negInt32(ptr %t40)
  %t42 = call ptr @v_render(ptr %t41)
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 0, label %case.arm.0.48 i64 1, label %case.arm.1.56 ]
case.arm.0.48:
  %t50 = getelementptr ptr, ptr %t42, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @malloc(i64 16)
  %t53 = inttoptr i64 0 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t51, ptr %t55
  br label %case.end.0.49
case.end.0.49:
  br label %case.join.47
case.arm.1.56:
  %t58 = getelementptr ptr, ptr %t42, i32 1
  %t59 = load ptr, ptr %t58
  %t60 = call ptr @v_maxInt32()
  %t61 = call ptr @__negInt32(ptr %t60)
  %t62 = call ptr @v_render(ptr %t61)
  %t63 = getelementptr ptr, ptr %t62, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 0, label %case.arm.0.68 i64 1, label %case.arm.1.76 ]
case.arm.0.68:
  %t70 = getelementptr ptr, ptr %t62, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 0 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  br label %case.end.0.69
case.end.0.69:
  br label %case.join.67
case.arm.1.76:
  %t78 = getelementptr ptr, ptr %t62, i32 1
  %t79 = load ptr, ptr %t78
  %t80 = call ptr @v_minInt32()
  %t81 = call ptr @__negInt32(ptr %t80)
  %t82 = call ptr @v_render(ptr %t81)
  %t83 = getelementptr ptr, ptr %t82, i32 0
  %t84 = load ptr, ptr %t83
  %t85 = ptrtoint ptr %t84 to i64
  switch i64 %t85, label %case.default.86 [ i64 0, label %case.arm.0.88 i64 1, label %case.arm.1.96 ]
case.arm.0.88:
  %t90 = getelementptr ptr, ptr %t82, i32 1
  %t91 = load ptr, ptr %t90
  %t92 = call ptr @malloc(i64 16)
  %t93 = inttoptr i64 0 to ptr
  %t94 = getelementptr ptr, ptr %t92, i32 0
  store ptr %t93, ptr %t94
  %t95 = getelementptr ptr, ptr %t92, i32 1
  store ptr %t91, ptr %t95
  br label %case.end.0.89
case.end.0.89:
  br label %case.join.87
case.arm.1.96:
  %t98 = getelementptr ptr, ptr %t82, i32 1
  %t99 = load ptr, ptr %t98
  %t100 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t101 = call ptr @__concat(ptr %t19, ptr %t100)
  %t102 = getelementptr ptr, ptr %t101, i32 0
  %t103 = load ptr, ptr %t102
  %t104 = ptrtoint ptr %t103 to i64
  switch i64 %t104, label %case.default.105 [ i64 0, label %case.arm.0.107 i64 1, label %case.arm.1.115 ]
case.arm.0.107:
  %t109 = getelementptr ptr, ptr %t101, i32 1
  %t110 = load ptr, ptr %t109
  %t111 = call ptr @malloc(i64 16)
  %t112 = inttoptr i64 0 to ptr
  %t113 = getelementptr ptr, ptr %t111, i32 0
  store ptr %t112, ptr %t113
  %t114 = getelementptr ptr, ptr %t111, i32 1
  store ptr %t110, ptr %t114
  br label %case.end.0.108
case.end.0.108:
  br label %case.join.106
case.arm.1.115:
  %t117 = getelementptr ptr, ptr %t101, i32 1
  %t118 = load ptr, ptr %t117
  %t119 = call ptr @__concat(ptr %t118, ptr %t39)
  %t120 = getelementptr ptr, ptr %t119, i32 0
  %t121 = load ptr, ptr %t120
  %t122 = ptrtoint ptr %t121 to i64
  switch i64 %t122, label %case.default.123 [ i64 0, label %case.arm.0.125 i64 1, label %case.arm.1.133 ]
case.arm.0.125:
  %t127 = getelementptr ptr, ptr %t119, i32 1
  %t128 = load ptr, ptr %t127
  %t129 = call ptr @malloc(i64 16)
  %t130 = inttoptr i64 0 to ptr
  %t131 = getelementptr ptr, ptr %t129, i32 0
  store ptr %t130, ptr %t131
  %t132 = getelementptr ptr, ptr %t129, i32 1
  store ptr %t128, ptr %t132
  br label %case.end.0.126
case.end.0.126:
  br label %case.join.124
case.arm.1.133:
  %t135 = getelementptr ptr, ptr %t119, i32 1
  %t136 = load ptr, ptr %t135
  %t137 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t138 = call ptr @__concat(ptr %t136, ptr %t137)
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
  %t156 = call ptr @__concat(ptr %t155, ptr %t59)
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
  %t174 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t175 = call ptr @__concat(ptr %t173, ptr %t174)
  %t176 = getelementptr ptr, ptr %t175, i32 0
  %t177 = load ptr, ptr %t176
  %t178 = ptrtoint ptr %t177 to i64
  switch i64 %t178, label %case.default.179 [ i64 0, label %case.arm.0.181 i64 1, label %case.arm.1.189 ]
case.arm.0.181:
  %t183 = getelementptr ptr, ptr %t175, i32 1
  %t184 = load ptr, ptr %t183
  %t185 = call ptr @malloc(i64 16)
  %t186 = inttoptr i64 0 to ptr
  %t187 = getelementptr ptr, ptr %t185, i32 0
  store ptr %t186, ptr %t187
  %t188 = getelementptr ptr, ptr %t185, i32 1
  store ptr %t184, ptr %t188
  br label %case.end.0.182
case.end.0.182:
  br label %case.join.180
case.arm.1.189:
  %t191 = getelementptr ptr, ptr %t175, i32 1
  %t192 = load ptr, ptr %t191
  %t193 = call ptr @__concat(ptr %t192, ptr %t79)
  %t194 = getelementptr ptr, ptr %t193, i32 0
  %t195 = load ptr, ptr %t194
  %t196 = ptrtoint ptr %t195 to i64
  switch i64 %t196, label %case.default.197 [ i64 0, label %case.arm.0.199 i64 1, label %case.arm.1.207 ]
case.arm.0.199:
  %t201 = getelementptr ptr, ptr %t193, i32 1
  %t202 = load ptr, ptr %t201
  %t203 = call ptr @malloc(i64 16)
  %t204 = inttoptr i64 0 to ptr
  %t205 = getelementptr ptr, ptr %t203, i32 0
  store ptr %t204, ptr %t205
  %t206 = getelementptr ptr, ptr %t203, i32 1
  store ptr %t202, ptr %t206
  br label %case.end.0.200
case.end.0.200:
  br label %case.join.198
case.arm.1.207:
  %t209 = getelementptr ptr, ptr %t193, i32 1
  %t210 = load ptr, ptr %t209
  %t211 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t212 = call ptr @__concat(ptr %t210, ptr %t211)
  %t213 = getelementptr ptr, ptr %t212, i32 0
  %t214 = load ptr, ptr %t213
  %t215 = ptrtoint ptr %t214 to i64
  switch i64 %t215, label %case.default.216 [ i64 0, label %case.arm.0.218 i64 1, label %case.arm.1.226 ]
case.arm.0.218:
  %t220 = getelementptr ptr, ptr %t212, i32 1
  %t221 = load ptr, ptr %t220
  %t222 = call ptr @malloc(i64 16)
  %t223 = inttoptr i64 0 to ptr
  %t224 = getelementptr ptr, ptr %t222, i32 0
  store ptr %t223, ptr %t224
  %t225 = getelementptr ptr, ptr %t222, i32 1
  store ptr %t221, ptr %t225
  br label %case.end.0.219
case.end.0.219:
  br label %case.join.217
case.arm.1.226:
  %t228 = getelementptr ptr, ptr %t212, i32 1
  %t229 = load ptr, ptr %t228
  %t230 = call ptr @__concat(ptr %t229, ptr %t99)
  br label %case.end.1.227
case.end.1.227:
  br label %case.join.217
case.default.216:
  unreachable
case.join.217:
  %t231 = phi ptr [%t222, %case.end.0.219], [%t230, %case.end.1.227]
  br label %case.end.1.208
case.end.1.208:
  br label %case.join.198
case.default.197:
  unreachable
case.join.198:
  %t232 = phi ptr [%t203, %case.end.0.200], [%t231, %case.end.1.208]
  br label %case.end.1.190
case.end.1.190:
  br label %case.join.180
case.default.179:
  unreachable
case.join.180:
  %t233 = phi ptr [%t185, %case.end.0.182], [%t232, %case.end.1.190]
  br label %case.end.1.171
case.end.1.171:
  br label %case.join.161
case.default.160:
  unreachable
case.join.161:
  %t234 = phi ptr [%t166, %case.end.0.163], [%t233, %case.end.1.171]
  br label %case.end.1.153
case.end.1.153:
  br label %case.join.143
case.default.142:
  unreachable
case.join.143:
  %t235 = phi ptr [%t148, %case.end.0.145], [%t234, %case.end.1.153]
  br label %case.end.1.134
case.end.1.134:
  br label %case.join.124
case.default.123:
  unreachable
case.join.124:
  %t236 = phi ptr [%t129, %case.end.0.126], [%t235, %case.end.1.134]
  br label %case.end.1.116
case.end.1.116:
  br label %case.join.106
case.default.105:
  unreachable
case.join.106:
  %t237 = phi ptr [%t111, %case.end.0.108], [%t236, %case.end.1.116]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t238 = phi ptr [%t92, %case.end.0.89], [%t237, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t239 = phi ptr [%t72, %case.end.0.69], [%t238, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t240 = phi ptr [%t52, %case.end.0.49], [%t239, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t241 = phi ptr [%t32, %case.end.0.29], [%t240, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t242 = phi ptr [%t12, %case.end.0.9], [%t241, %case.end.1.17]
  %t243 = call ptr @v__let_2(ptr %t242)
  ret ptr %t243
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
  %t12 = getelementptr [16 x i8], ptr @.str.4, i64 0, i64 0
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
