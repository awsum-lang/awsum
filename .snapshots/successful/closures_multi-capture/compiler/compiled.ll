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

@.str.0 = private unnamed_addr constant [2 x i8] c"/\00"

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


define internal ptr @v_zero() {
  %t0 = call ptr @malloc(i64 4)
  store i32 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_both(ptr %v_a, ptr %v_b) {
  %t0 = call ptr @v_zero()
  %t1 = call ptr @v__df_apply_0(ptr %t0, ptr %v_a, ptr %v_b)
  ret ptr %t1
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 11, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 22, ptr %t1
  %t2 = call ptr @v_both(ptr %t0, ptr %t1)
  %t3 = call ptr @__print(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__lam_1(ptr %v_a, ptr %v_b, ptr %v__n) {
  %t0 = call ptr @__showInt32(ptr %v_a)
  %t1 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t2 = call ptr @__concat(ptr %t0, ptr %t1)
  %t3 = call ptr @__showInt32(ptr %v_b)
  %t4 = call ptr @__concat(ptr %t2, ptr %t3)
  ret ptr %t4
}

define internal ptr @v__df_apply_0(ptr %v_x, ptr %v__df_apply_0_cap0_0, ptr %v__df_apply_0_cap0_1) {
  %t0 = call ptr @v__lam_1(ptr %v__df_apply_0_cap0_0, ptr %v__df_apply_0_cap0_1, ptr %v_x)
  ret ptr %t0
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
