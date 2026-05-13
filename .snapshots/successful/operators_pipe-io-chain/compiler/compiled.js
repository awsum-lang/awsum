"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
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

const main = (v__df_andThenIO_0)((v__df_andThenIO_2)((v__lift_8)([7, "a", [5, [0]]])));

function v__lift_1(v___input){
    return (v__cps__lift_1)(v___input, [18]);
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
          const __t1 = (v___input[0] = 19, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [11, v___f0]]);
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
        case 18: {
          return v__x;
        }
        case 19: {
          const v__pk_19 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_19;
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

function v__lam_7(v__u){
    return [7, "c", [5, [0]]];
}

function v__lift_8(v___input){
    return (v__cps__lift_8)(v___input, [20]);
}

function v__cps__lift_8(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_8)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_8)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 21, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_8)(v__k, [8, [12, v___f0]]);
        }
      }
    }
  }
}

function v__apply__lift_8(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
          const v__pk_21 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_21;
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

function v__lam_10(v__u){
    return (v__lift_8)([7, "b", [5, [0]]]);
}

function v__df_andThenIO_0(v_io){
    return (v__cps__df_andThenIO_0)(v_io, [22]);
}

function v__cps__df_andThenIO_0(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, (v__lift_1)((v__lam_7)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 23, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [8, [9, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_andThenIO_0(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 22: {
          return v__x;
        }
        case 23: {
          const v__pk_23 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_23;
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
    return (v__cps__df_andThenIO_2)(v_io, [24]);
}

function v__cps__df_andThenIO_2(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, (v__lift_1)((v__lam_10)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 25, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [8, [10, v_cont]]);
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
        case 24: {
          return v__x;
        }
        case 25: {
          const v__pk_25 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_25;
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

function v__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9(v__args){
    return (v__cps__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9)(v__args, [26]);
}

function v__cps__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9(v__args, v__k){
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
                const v__cap11_0 = __s[1];
                const __t0 = (v__args[0] = 16, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 12: {
                const v__cap12_0 = __s[1];
                const __t0 = (v__args[0] = 17, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
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
          const __t1 = [27, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 15: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 13, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [28, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 16: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 13, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [29, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 17: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 13, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [30, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply1(v__cl, v__arg0){
    return (v__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9)([13, v__cl, v__arg0]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();