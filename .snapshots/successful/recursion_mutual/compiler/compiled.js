"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = __t0;
                continue;
              }
            }
          }
        }
        case 3: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = __t0;
          continue;
        }
      }
    }
  }
}

const main = (v__let_7)((v_handleA)([0]));

function v__let_7(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

function v__apply1(v__cl, v__arg0){
    {
      const __s = v__cl;
      switch (__s[0]) {
      }
    }
}

function v__scc_handleA_handleB(v__args){
    return (v__cps__scc_handleA_handleB)(v__args, [0]);
}

function v__cps__scc_handleA_handleB(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 0: {
                const __t0 = [1, [1]];
                const __t1 = [1, v__k];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 1: {
                const __t0 = [1, v_step];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 2: {
                const __t0 = [1, v_step];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 3: {
                return (v__apply__scc_handleA_handleB)(v__k, [1, ""]);
              }
            }
          }
        }
        case 1: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 0: {
                const __t0 = [0, v_step];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 1: {
                const __t0 = [0, [2]];
                const __t1 = [2, v__k];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 2: {
                const __t0 = [0, [3]];
                const __t1 = [3, v__k];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 3: {
                return (v__apply__scc_handleA_handleB)(v__k, [1, ""]);
              }
            }
          }
        }
      }
    }
  }
}

function v__apply__scc_handleA_handleB(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v__do_e_9_5 = __s[1];
                const __t0 = v__pk_1;
                const __t1 = [0, v__do_e_9_5];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_rest = __s[1];
                const __t0 = v__pk_1;
                const __t1 = __concat("A", v_rest);
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
        case 2: {
          const v__pk_2 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v__do_e_18_5 = __s[1];
                const __t0 = v__pk_2;
                const __t1 = [0, v__do_e_18_5];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_rest = __s[1];
                const __t0 = v__pk_2;
                const __t1 = __concat("B", v_rest);
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
        case 3: {
          const v__pk_3 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v__do_e_22_5 = __s[1];
                const __t0 = v__pk_3;
                const __t1 = [0, v__do_e_22_5];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_rest = __s[1];
                const __t0 = v__pk_3;
                const __t1 = __concat("C", v_rest);
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_handleA(v_step){
    return (v__scc_handleA_handleB)([0, v_step]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();