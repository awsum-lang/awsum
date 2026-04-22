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

@.str.0 = private unnamed_addr constant [6 x i8] c"Hello\00"
@.str.1 = private unnamed_addr constant [3 x i8] c", \00"
@.str.2 = private unnamed_addr constant [2 x i8] c"!\00"

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
  %t0 = call ptr @v_addGreeting(ptr %v_input)
  %t1 = call ptr @__print(ptr %t0)
  ret ptr %t1
}

define ptr @v_greeting() {
  %t0 = getelementptr [6 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define ptr @v_addGreeting(ptr %v_name) {
  %t0 = call ptr @v_greeting()
  %t1 = getelementptr [3 x i8], ptr @.str.1, i64 0, i64 0
  %t2 = call ptr @__concat(ptr %t0, ptr %t1)
  %t3 = call ptr @__concat(ptr %t2, ptr %v_name)
  %t4 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t5 = call ptr @__concat(ptr %t3, ptr %t4)
  ret ptr %t5
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
