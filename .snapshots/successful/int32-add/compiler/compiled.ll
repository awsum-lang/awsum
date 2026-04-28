; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [10 x i8] c"Underflow\00"
@.str.1 = private unnamed_addr constant [9 x i8] c"Overflow\00"
@.str.2 = private unnamed_addr constant [6 x i8] c"err: \00"
@.str.3 = private unnamed_addr constant [5 x i8] c"ok: \00"
@.str.4 = private unnamed_addr constant [3 x i8] c", \00"

define ptr @__concat(ptr %a, ptr %b) {
  %la = call i64 @strlen(ptr %a)
  %lb = call i64 @strlen(ptr %b)
  %sum = add i64 %la, %lb
  %total = add i64 %sum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  ret ptr %buf
}


define ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  ret ptr null
}


define ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define ptr @__addInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
  %sum = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %is_pos = icmp sge i32 %a, 0
  %ae_tag_idx = select i1 %is_pos, i64 1, i64 0
  %ae = call ptr @malloc(i64 8)
  %ae_tag = inttoptr i64 %ae_tag_idx to ptr
  store ptr %ae_tag, ptr %ae
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %ae, ptr %left_f
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


define ptr @v_showArithError(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [10 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [9 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t11 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9]
  ret ptr %t11
}

define ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  %t10 = call ptr @v_showArithError(ptr %t8)
  %t11 = call ptr @__concat(ptr %t9, ptr %t10)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_r, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr [5 x i8], ptr @.str.3, i64 0, i64 0
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

define ptr @v_maxInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 2147483647, ptr %t0
  ret ptr %t0
}

define ptr @v_minInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t0
  ret ptr %t0
}

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 100, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 23, ptr %t1
  %t2 = call ptr @__addInt32(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t5 = call ptr @__concat(ptr %t3, ptr %t4)
  %t6 = call ptr @malloc(i64 4)
  store i32 100, ptr %t6
  %t7 = call ptr @malloc(i64 4)
  store i32 -50, ptr %t7
  %t8 = call ptr @__addInt32(ptr %t6, ptr %t7)
  %t9 = call ptr @v_render(ptr %t8)
  %t10 = call ptr @__concat(ptr %t5, ptr %t9)
  %t11 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %t10, ptr %t11)
  %t13 = call ptr @v_maxInt32()
  %t14 = call ptr @malloc(i64 4)
  store i32 1, ptr %t14
  %t15 = call ptr @__addInt32(ptr %t13, ptr %t14)
  %t16 = call ptr @v_render(ptr %t15)
  %t17 = call ptr @__concat(ptr %t12, ptr %t16)
  %t18 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t19 = call ptr @__concat(ptr %t17, ptr %t18)
  %t20 = call ptr @v_minInt32()
  %t21 = call ptr @malloc(i64 4)
  store i32 -1, ptr %t21
  %t22 = call ptr @__addInt32(ptr %t20, ptr %t21)
  %t23 = call ptr @v_render(ptr %t22)
  %t24 = call ptr @__concat(ptr %t19, ptr %t23)
  %t25 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t26 = call ptr @__concat(ptr %t24, ptr %t25)
  %t27 = call ptr @v_maxInt32()
  %t28 = call ptr @v_minInt32()
  %t29 = call ptr @__addInt32(ptr %t27, ptr %t28)
  %t30 = call ptr @v_render(ptr %t29)
  %t31 = call ptr @__concat(ptr %t26, ptr %t30)
  %t32 = call ptr @__print(ptr %t31)
  ret ptr %t32
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
