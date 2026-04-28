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
@.str.6 = private unnamed_addr constant [3 x i8] c", \00"
@.str.7 = private unnamed_addr constant [3 x i8] c"::\00"
@.str.8 = private unnamed_addr constant [16 x i8] c"user::42::admin\00"
@.str.9 = private unnamed_addr constant [2 x i8] c"x\00"
@.str.10 = private unnamed_addr constant [4 x i8] c"abc\00"
@.str.11 = private unnamed_addr constant [1 x i8] c"\00"
@.str.12 = private unnamed_addr constant [2 x i8] c":\00"
@.str.13 = private unnamed_addr constant [5 x i8] c":foo\00"
@.str.14 = private unnamed_addr constant [5 x i8] c"foo:\00"
@.str.15 = private unnamed_addr constant [6 x i8] c"abcde\00"
@.str.16 = private unnamed_addr constant [3 x i8] c"ab\00"

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


define ptr @__splitOnFirst(ptr %sep, ptr %str) {
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


define ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [8 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr ptr, ptr %v_r, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 0, label %case.arm.0.17 ]
case.arm.0.17:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = getelementptr ptr, ptr %t11, i32 2
  %t22 = load ptr, ptr %t21
  %t23 = getelementptr [6 x i8], ptr @.str.1, i64 0, i64 0
  %t24 = call ptr @__concat(ptr %t23, ptr %t20)
  %t25 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t26 = call ptr @__concat(ptr %t24, ptr %t25)
  %t27 = call ptr @__concat(ptr %t26, ptr %t22)
  %t28 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t29 = call ptr @__concat(ptr %t27, ptr %t28)
  br label %case.end.0.18
case.end.0.18:
  br label %case.join.16
case.default.15:
  unreachable
case.join.16:
  %t30 = phi ptr [%t29, %case.end.0.18]
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t31 = phi ptr [%t7, %case.end.0.6], [%t30, %case.end.1.9]
  ret ptr %t31
}

define ptr @v_main(ptr %v__input) {
  %t0 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t1 = getelementptr [6 x i8], ptr @.str.5, i64 0, i64 0
  %t2 = call ptr @__splitOnFirst(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t5 = call ptr @__concat(ptr %t3, ptr %t4)
  %t6 = getelementptr [3 x i8], ptr @.str.7, i64 0, i64 0
  %t7 = getelementptr [16 x i8], ptr @.str.8, i64 0, i64 0
  %t8 = call ptr @__splitOnFirst(ptr %t6, ptr %t7)
  %t9 = call ptr @v_render(ptr %t8)
  %t10 = call ptr @__concat(ptr %t5, ptr %t9)
  %t11 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %t10, ptr %t11)
  %t13 = getelementptr [2 x i8], ptr @.str.9, i64 0, i64 0
  %t14 = getelementptr [4 x i8], ptr @.str.10, i64 0, i64 0
  %t15 = call ptr @__splitOnFirst(ptr %t13, ptr %t14)
  %t16 = call ptr @v_render(ptr %t15)
  %t17 = call ptr @__concat(ptr %t12, ptr %t16)
  %t18 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t19 = call ptr @__concat(ptr %t17, ptr %t18)
  %t20 = getelementptr [1 x i8], ptr @.str.11, i64 0, i64 0
  %t21 = getelementptr [4 x i8], ptr @.str.10, i64 0, i64 0
  %t22 = call ptr @__splitOnFirst(ptr %t20, ptr %t21)
  %t23 = call ptr @v_render(ptr %t22)
  %t24 = call ptr @__concat(ptr %t19, ptr %t23)
  %t25 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t26 = call ptr @__concat(ptr %t24, ptr %t25)
  %t27 = getelementptr [2 x i8], ptr @.str.12, i64 0, i64 0
  %t28 = getelementptr [5 x i8], ptr @.str.13, i64 0, i64 0
  %t29 = call ptr @__splitOnFirst(ptr %t27, ptr %t28)
  %t30 = call ptr @v_render(ptr %t29)
  %t31 = call ptr @__concat(ptr %t26, ptr %t30)
  %t32 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t33 = call ptr @__concat(ptr %t31, ptr %t32)
  %t34 = getelementptr [2 x i8], ptr @.str.12, i64 0, i64 0
  %t35 = getelementptr [5 x i8], ptr @.str.14, i64 0, i64 0
  %t36 = call ptr @__splitOnFirst(ptr %t34, ptr %t35)
  %t37 = call ptr @v_render(ptr %t36)
  %t38 = call ptr @__concat(ptr %t33, ptr %t37)
  %t39 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t40 = call ptr @__concat(ptr %t38, ptr %t39)
  %t41 = getelementptr [4 x i8], ptr @.str.10, i64 0, i64 0
  %t42 = getelementptr [4 x i8], ptr @.str.10, i64 0, i64 0
  %t43 = call ptr @__splitOnFirst(ptr %t41, ptr %t42)
  %t44 = call ptr @v_render(ptr %t43)
  %t45 = call ptr @__concat(ptr %t40, ptr %t44)
  %t46 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t47 = call ptr @__concat(ptr %t45, ptr %t46)
  %t48 = getelementptr [6 x i8], ptr @.str.15, i64 0, i64 0
  %t49 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t50 = call ptr @__splitOnFirst(ptr %t48, ptr %t49)
  %t51 = call ptr @v_render(ptr %t50)
  %t52 = call ptr @__concat(ptr %t47, ptr %t51)
  %t53 = call ptr @__print(ptr %t52)
  ret ptr %t53
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
