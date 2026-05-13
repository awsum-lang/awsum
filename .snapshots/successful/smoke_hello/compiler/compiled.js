"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [15]] : [4, a + b]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [15]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [16]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [16]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [16]]]; } return [4, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_u = __s[1];
          return v_u;
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = null;
                v_io = __t0;
                continue;
              }
            }
          }
        }
        case 8: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = null;
          v_io = __t0;
          continue;
        }
      }
    }
  }
}

const main = (v__df_handleErrorIO_0)((v__df_andThenIO_2)([8, [11]]));

function v_greetAndPrint(v_input){
    {
      const __s = (v_addGreeting)(v_input);
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
}

function v_printDecodeError(v_e){
    {
      const __s = v_e;
      switch (__s[0]) {
        case 502975519: {
          const v__u = __s[1];
          return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
        }
        case 589989748: {
          const v__l = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
}

const v_greeting = "Hello";

function v_addGreeting(v_name){
    {
      const __s = __concat(v_greeting, ", ");
      switch (__s[0]) {
        case 3: {
          const v__do_e_27_3 = __s[1];
          return [3, v__do_e_27_3];
        }
        case 4: {
          const v_s0 = __s[1];
          {
            const __s = __concat(v_s0, v_name);
            switch (__s[0]) {
              case 3: {
                const v__do_e_28_3 = __s[1];
                return [3, v__do_e_28_3];
              }
              case 4: {
                const v_s1 = __s[1];
                return __concat(v_s1, "!");
              }
            }
          }
        }
      }
    }
}

function v__lift_1(v___input){
    return (v__cps__lift_1)(v___input, [17]);
}

function v__cps__lift_1(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 18, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [12, v___f0]]);
        }
      }
    }
  }
}

function v__apply__lift_1(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 17: {
          return v__x;
        }
        case 18: {
          const v__pk_18 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_18;
          const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__io_getargs_cont(v_result){
    {
      const __s = v_result;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [6, v_e];
        }
        case 4: {
          const v_s = __s[1];
          return [5, v_s];
        }
      }
    }
}

function v__df_handleErrorIO_0(v_io){
    return (v__cps__df_handleErrorIO_0)(v_io, [19]);
}

function v__cps__df_handleErrorIO_0(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, (v_printDecodeError)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 20, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [8, [10, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_handleErrorIO_0(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 19: {
          return v__x;
        }
        case 20: {
          const v__pk_20 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_20;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__df_andThenIO_2(v_io){
    return (v__cps__df_andThenIO_2)(v_io, [21]);
}

function v__cps__df_andThenIO_2(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, (v__lift_1)((v_greetAndPrint)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 22, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [8, [9, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_andThenIO_2(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 21: {
          return v__x;
        }
        case 22: {
          const v__pk_22 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_22;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2(v__args){
    return (v__cps__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2)(v__args, [23]);
}

function v__cps__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 13: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 9: {
                const v__cap9_0 = __s[1];
                const __t0 = (v__args[0] = 14, v__args[1] = v__cap9_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 10: {
                const v__cap10_0 = __s[1];
                const __t0 = (v__args[0] = 15, v__args[1] = v__cap10_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 11: {
                return (v__apply__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2)(v__k, (v__io_getargs_cont)(v__arg0));
              }
              case 12: {
                const v__cap12_0 = __s[1];
                const __t0 = (v__args[0] = 16, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 14: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 13, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [24, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 15: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 13, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [25, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 16: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 13, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [26, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 23: {
          return v__x;
        }
        case 24: {
          const v__pk_24 = __s[1];
          const __t0 = v__pk_24;
          const __t1 = (v__df_andThenIO_2)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 25: {
          const v__pk_25 = __s[1];
          const __t0 = v__pk_25;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 26: {
          const v__pk_26 = __s[1];
          const __t0 = v__pk_26;
          const __t1 = (v__lift_1)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply1(v__cl, v__arg0){
    return (v__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2)([13, v__cl, v__arg0]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();