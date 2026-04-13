; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [2 x i8] c"a\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"b\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"x\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"y\00"

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

define ptr @v_main(ptr %v_input) {
  %t0 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t1 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t2 = call ptr @v_const(ptr %t0, ptr %t1)
  %t3 = call ptr @v_compose(ptr @v_appendY, ptr @v_appendX, ptr %t2)
  %t4 = call ptr @v_identity(ptr %t3)
  %t5 = call ptr @__print(ptr %t4)
  ret ptr %t5
}

define ptr @v_const(ptr %v_x, ptr %v_y) {
  ret ptr %v_x
}

define ptr @v_identity(ptr %v_x) {
  ret ptr %v_x
}

define ptr @v_appendX(ptr %v_s) {
  %t0 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t1 = call ptr @__concat(ptr %v_s, ptr %t0)
  ret ptr %t1
}

define ptr @v_appendY(ptr %v_s) {
  %t0 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t1 = call ptr @__concat(ptr %v_s, ptr %t0)
  ret ptr %t1
}

define ptr @v_compose(ptr %v_g, ptr %v_f, ptr %v_x) {
  %t0 = call ptr %v_f(ptr %v_x)
  %t1 = call ptr %v_g(ptr %t0)
  ret ptr %t1
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
