"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [16]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [17]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [17]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [17]]]; } return [4, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

function v_pureIO(v_x){
    return [5, v_x];
}

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
        case 9: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __stdinReadAll());
          v_io = null;
          v_io = __t0;
          continue;
        }
      }
    }
  }
}

const v_source = (v_pureIO)("before");

const main = (v__df_bindIO_0)((v__df_mapIO_3)(v_source));

function v__lift_1(v___input){
    return (v__cps__lift_1)(v___input, [23]);
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
          const __t1 = (v___input[0] = 24, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [14, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [15, v___f0]]);
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
        case 23: {
          return v__x;
        }
        case 24: {
          const v__pk_24 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_24;
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

function v__lam_12(v__s){
    return "after";
}

function v__bi_IO_Stdout_print(v__x0){
    return [7, v__x0, [5, [0]]];
}

function v__df_bindIO_0(v_io){
    return (v__cps__df_bindIO_0)(v_io, [25]);
}

function v__cps__df_bindIO_0(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_bindIO_0)(v__k, (v__lift_1)((v__bi_IO_Stdout_print)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_bindIO_0)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 26, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_bindIO_0)(v__k, [8, [12, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_bindIO_0)(v__k, [9, [13, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_bindIO_0(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_26;
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

function v__df_mapIO_3(v_io){
    return (v__cps__df_mapIO_3)(v_io, [27]);
}

function v__cps__df_mapIO_3(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_mapIO_3)(v__k, [5, (v__lam_12)(v_a)]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_mapIO_3)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 28, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_mapIO_3)(v__k, [8, [10, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_mapIO_3)(v__k, [9, [11, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_mapIO_3(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_28;
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

function v__scc__apply1__df__lam_6_4__df__lam_7_5__df_bindIOAfterArgs_1__df_bindIOAfterStdin_2__lift_2__lift_3(v__args){
    return (v__cps__scc__apply1__df__lam_6_4__df__lam_7_5__df_bindIOAfterArgs_1__df_bindIOAfterStdin_2__lift_2__lift_3)(v__args, [29]);
}

function v__cps__scc__apply1__df__lam_6_4__df__lam_7_5__df_bindIOAfterArgs_1__df_bindIOAfterStdin_2__lift_2__lift_3(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 16: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 10: {
                const v__cap10_0 = __s[1];
                const __t0 = (v__args[0] = 17, v__args[1] = v__cap10_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 11: {
                const v__cap11_0 = __s[1];
                const __t0 = (v__args[0] = 18, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 12: {
                const v__cap12_0 = __s[1];
                const __t0 = (v__args[0] = 19, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 13: {
                const v__cap13_0 = __s[1];
                const __t0 = (v__args[0] = 20, v__args[1] = v__cap13_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 14: {
                const v__cap14_0 = __s[1];
                const __t0 = (v__args[0] = 21, v__args[1] = v__cap14_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 15: {
                const v__cap15_0 = __s[1];
                const __t0 = (v__args[0] = 22, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 17: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 16, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [30, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 18: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 16, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [31, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 19: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 16, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [32, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 20: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 16, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [33, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 21: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 16, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [34, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 22: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 16, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [35, v__k];
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
    return (v__scc__apply1__df__lam_6_4__df__lam_7_5__df_bindIOAfterArgs_1__df_bindIOAfterStdin_2__lift_2__lift_3)([16, v__cl, v__arg0]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();