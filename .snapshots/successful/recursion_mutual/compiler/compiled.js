"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [15]] : [4, a + b]; }

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
      }
    }
  }
}

const main = (v__let_7)((v_handleA)([19]));

function v__let_7(v_res){
    {
      const __s = v_res;
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

function v__scc_handleA_handleB(v__args){
    return (v__cps__scc_handleA_handleB)(v__args, [25]);
}

function v__cps__scc_handleA_handleB(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 23: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 19: {
                const __t0 = (v__args[0] = 24, v__args[1] = [20], v__args);
                const __t1 = [26, v__k];
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 20: {
                const __t0 = (v__args[0] = 24, v__args[1] = v_step, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 21: {
                const __t0 = (v__args[0] = 24, v__args[1] = v_step, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 22: {
                return (v__apply__scc_handleA_handleB)(v__k, [4, ""]);
              }
            }
          }
        }
        case 24: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 19: {
                const __t0 = (v__args[0] = 23, v__args[1] = v_step, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 20: {
                const __t0 = (v__args[0] = 23, v__args[1] = [21], v__args);
                const __t1 = [27, v__k];
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 21: {
                const __t0 = (v__args[0] = 23, v__args[1] = [22], v__args);
                const __t1 = [28, v__k];
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 22: {
                return (v__apply__scc_handleA_handleB)(v__k, [4, ""]);
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
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_13_5 = __s[1];
                const __t0 = v__pk_26;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_13_5, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_26;
                const __t1 = __concat("A", v_rest);
                v__x = null;
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
        case 27: {
          const v__pk_27 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_22_5 = __s[1];
                const __t0 = v__pk_27;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_22_5, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_27;
                const __t1 = __concat("B", v_rest);
                v__x = null;
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
        case 28: {
          const v__pk_28 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_26_5 = __s[1];
                const __t0 = v__pk_28;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_26_5, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_28;
                const __t1 = __concat("C", v_rest);
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
    }
  }
}

function v_handleA(v_step){
    return (v__scc_handleA_handleB)([23, v_step]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();