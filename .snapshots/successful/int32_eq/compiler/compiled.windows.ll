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

@.str.0 = private unnamed_addr constant [2 x i8] c"T\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"F\00"
@.str.2 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__eqInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 0, i64 1
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  ret ptr %box
}


define internal ptr @v_minInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t11 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9]
  ret ptr %t11
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 42, ptr %t3
  %t4 = call ptr @malloc(i64 4)
  store i32 42, ptr %t4
  %t5 = call ptr @__eqInt32(ptr %t3, ptr %t4)
  %t6 = call ptr @v_render(ptr %t5)
  %t7 = call ptr @malloc(i64 4)
  store i32 42, ptr %t7
  %t8 = call ptr @malloc(i64 4)
  store i32 7, ptr %t8
  %t9 = call ptr @__eqInt32(ptr %t7, ptr %t8)
  %t10 = call ptr @v_render(ptr %t9)
  %t11 = call ptr @__concat(ptr %t6, ptr %t10)
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t0, i32 0
  %t14 = load ptr, ptr %t13
  %t15 = ptrtoint ptr %t14 to i64
  switch i64 %t15, label %case.default.16 [ i64 0, label %case.arm.0.18 i64 1, label %case.arm.1.26 ]
case.arm.0.18:
  %t20 = getelementptr ptr, ptr %t0, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @malloc(i64 16)
  %t23 = inttoptr i64 0 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  br label %case.end.0.19
case.end.0.19:
  br label %case.join.17
case.arm.1.26:
  %t28 = getelementptr ptr, ptr %t0, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 1 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @v_minInt32()
  %t34 = call ptr @v_minInt32()
  %t35 = call ptr @__eqInt32(ptr %t33, ptr %t34)
  %t36 = call ptr @v_render(ptr %t35)
  %t37 = call ptr @__concat(ptr %t29, ptr %t36)
  %t38 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t30, i32 0
  %t40 = load ptr, ptr %t39
  %t41 = ptrtoint ptr %t40 to i64
  switch i64 %t41, label %case.default.42 [ i64 0, label %case.arm.0.44 i64 1, label %case.arm.1.52 ]
case.arm.0.44:
  %t46 = getelementptr ptr, ptr %t30, i32 1
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
  %t54 = getelementptr ptr, ptr %t30, i32 1
  %t55 = load ptr, ptr %t54
  %t56 = call ptr @malloc(i64 16)
  %t57 = inttoptr i64 1 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @malloc(i64 4)
  store i32 0, ptr %t59
  %t60 = call ptr @malloc(i64 4)
  store i32 1, ptr %t60
  %t61 = call ptr @__eqInt32(ptr %t59, ptr %t60)
  %t62 = call ptr @v_render(ptr %t61)
  %t63 = call ptr @__concat(ptr %t55, ptr %t62)
  %t64 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t63, ptr %t64
  br label %case.end.1.53
case.end.1.53:
  br label %case.join.43
case.default.42:
  unreachable
case.join.43:
  %t65 = phi ptr [%t48, %case.end.0.45], [%t56, %case.end.1.53]
  br label %case.end.1.27
case.end.1.27:
  br label %case.join.17
case.default.16:
  unreachable
case.join.17:
  %t66 = phi ptr [%t22, %case.end.0.19], [%t65, %case.end.1.27]
  %t67 = call ptr @v__let_1(ptr %t66)
  ret ptr %t67
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.2, i64 0, i64 0
  %t10 = call ptr @__print(ptr %t9)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_res, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__print(ptr %t14)
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t16 = phi ptr [%t10, %case.end.0.6], [%t15, %case.end.1.12]
  ret ptr %t16
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
  call ptr @v_main(ptr %right_box)
  ret i32 0
}
