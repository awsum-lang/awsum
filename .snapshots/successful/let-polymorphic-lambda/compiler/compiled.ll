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

@.str.0 = private unnamed_addr constant [2 x i8] c"A\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"B\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"C\00"
@.str.3 = private unnamed_addr constant [6 x i8] c"hello\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"/\00"

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @v_showTri(ptr %v_t) {
  %t0 = getelementptr ptr, ptr %v_t, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 i64 2, label %case.arm.2.11 ]
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
case.arm.2.11:
  %t13 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.2.12
case.end.2.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t14 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9], [%t13, %case.end.2.12]
  ret ptr %t14
}

define internal ptr @v_threeTypes(ptr %v_n, ptr %v_s, ptr %v_b) {
  %t0 = call ptr @v__df__let_1_0(ptr %v_b, ptr %v_n, ptr %v_s)
  ret ptr %t0
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 42, ptr %t0
  %t1 = getelementptr [6 x i8], ptr @.str.3, i64 0, i64 0
  %t2 = call ptr @malloc(i64 8)
  %t3 = inttoptr i64 0 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_threeTypes(ptr %t0, ptr %t1, ptr %t2)
  %t6 = call ptr @__print(ptr %t5)
  ret ptr %t6
}

define internal ptr @v__lam_0(ptr %v_x) {
  ret ptr %v_x
}

define internal ptr @v__df__let_1_0(ptr %v_b, ptr %v_n, ptr %v_s) {
  %t0 = call ptr @v__lam_0(ptr %v_n)
  %t1 = call ptr @__showInt32(ptr %t0)
  %t2 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t3 = call ptr @__concat(ptr %t1, ptr %t2)
  %t4 = call ptr @v__lam_0(ptr %v_s)
  %t5 = call ptr @__concat(ptr %t3, ptr %t4)
  %t6 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t7 = call ptr @__concat(ptr %t5, ptr %t6)
  %t8 = call ptr @v__lam_0(ptr %v_b)
  %t9 = call ptr @v_showTri(ptr %t8)
  %t10 = call ptr @__concat(ptr %t7, ptr %t9)
  ret ptr %t10
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
