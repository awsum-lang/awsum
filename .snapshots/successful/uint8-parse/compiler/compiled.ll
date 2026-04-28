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

@.str.0 = private unnamed_addr constant [4 x i8] c"err\00"
@.str.1 = private unnamed_addr constant [4 x i8] c"ok:\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"0\00"
@.str.3 = private unnamed_addr constant [3 x i8] c", \00"
@.str.4 = private unnamed_addr constant [4 x i8] c"255\00"
@.str.5 = private unnamed_addr constant [4 x i8] c"256\00"
@.str.6 = private unnamed_addr constant [3 x i8] c"-1\00"
@.str.7 = private unnamed_addr constant [1 x i8] c"\00"
@.str.8 = private unnamed_addr constant [4 x i8] c"abc\00"
@.str.9 = private unnamed_addr constant [3 x i8] c" 5\00"
@.str.10 = private unnamed_addr constant [4 x i8] c"12a\00"

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


define ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define ptr @__parseUInt8(ptr %s) {
entry:
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i32, align 4
  store i32 0, ptr %acc_alloca
  %len = call i64 @strlen(ptr %s)
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i32, ptr %acc_alloca
  %cond = icmp ult i64 %i, %len
  br i1 %cond, label %body, label %ok
body:
  %ptr_c = getelementptr i8, ptr %s, i64 %i
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


define ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = getelementptr ptr, ptr %v_r, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr [4 x i8], ptr @.str.1, i64 0, i64 0
  %t15 = call ptr @__showUInt8(ptr %t13)
  %t16 = call ptr @__concat(ptr %t14, ptr %t15)
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t9, %case.end.0.6], [%t16, %case.end.1.11]
  ret ptr %t17
}

define ptr @v_main(ptr %v__input) {
  %t0 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t1 = call ptr @__parseUInt8(ptr %t0)
  %t2 = call ptr @v_render(ptr %t1)
  %t3 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t4 = call ptr @__concat(ptr %t2, ptr %t3)
  %t5 = getelementptr [4 x i8], ptr @.str.4, i64 0, i64 0
  %t6 = call ptr @__parseUInt8(ptr %t5)
  %t7 = call ptr @v_render(ptr %t6)
  %t8 = call ptr @__concat(ptr %t4, ptr %t7)
  %t9 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t10 = call ptr @__concat(ptr %t8, ptr %t9)
  %t11 = getelementptr [4 x i8], ptr @.str.5, i64 0, i64 0
  %t12 = call ptr @__parseUInt8(ptr %t11)
  %t13 = call ptr @v_render(ptr %t12)
  %t14 = call ptr @__concat(ptr %t10, ptr %t13)
  %t15 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t16 = call ptr @__concat(ptr %t14, ptr %t15)
  %t17 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t18 = call ptr @__parseUInt8(ptr %t17)
  %t19 = call ptr @v_render(ptr %t18)
  %t20 = call ptr @__concat(ptr %t16, ptr %t19)
  %t21 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t22 = call ptr @__concat(ptr %t20, ptr %t21)
  %t23 = getelementptr [1 x i8], ptr @.str.7, i64 0, i64 0
  %t24 = call ptr @__parseUInt8(ptr %t23)
  %t25 = call ptr @v_render(ptr %t24)
  %t26 = call ptr @__concat(ptr %t22, ptr %t25)
  %t27 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t28 = call ptr @__concat(ptr %t26, ptr %t27)
  %t29 = getelementptr [4 x i8], ptr @.str.8, i64 0, i64 0
  %t30 = call ptr @__parseUInt8(ptr %t29)
  %t31 = call ptr @v_render(ptr %t30)
  %t32 = call ptr @__concat(ptr %t28, ptr %t31)
  %t33 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t34 = call ptr @__concat(ptr %t32, ptr %t33)
  %t35 = getelementptr [3 x i8], ptr @.str.9, i64 0, i64 0
  %t36 = call ptr @__parseUInt8(ptr %t35)
  %t37 = call ptr @v_render(ptr %t36)
  %t38 = call ptr @__concat(ptr %t34, ptr %t37)
  %t39 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t40 = call ptr @__concat(ptr %t38, ptr %t39)
  %t41 = getelementptr [4 x i8], ptr @.str.10, i64 0, i64 0
  %t42 = call ptr @__parseUInt8(ptr %t41)
  %t43 = call ptr @v_render(ptr %t42)
  %t44 = call ptr @__concat(ptr %t40, ptr %t43)
  %t45 = call ptr @__print(ptr %t44)
  ret ptr %t45
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
