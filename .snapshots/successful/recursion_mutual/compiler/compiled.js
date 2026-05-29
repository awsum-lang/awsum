"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

const v_runIO = (v_io) => {
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
};

const v__let_12 = (v_res) => {
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
};

const v__apply__scc_handleA_handleB = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          const v__pk_29 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                const __t0 = v__pk_29;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_0, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_29;
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
        case 30: {
          const v__pk_30 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_1 = __s[1];
                const __t0 = v__pk_30;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_1, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_30;
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
        case 31: {
          const v__pk_31 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_2 = __s[1];
                const __t0 = v__pk_31;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_2, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_31;
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
};

const v__cps__scc_handleA_handleB = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 26: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 22: {
                const __t0 = (v__args[0] = 27, v__args[1] = [23], v__args);
                const __t1 = [29, v__k];
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 23: {
                const __t0 = (v__args[0] = 27, v__args[1] = v_step, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 24: {
                const __t0 = (v__args[0] = 27, v__args[1] = v_step, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 25: {
                return (v__apply__scc_handleA_handleB)(v__k, [4, ""]);
              }
            }
          }
        }
        case 27: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 22: {
                const __t0 = (v__args[0] = 26, v__args[1] = v_step, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 23: {
                const __t0 = (v__args[0] = 26, v__args[1] = [24], v__args);
                const __t1 = [30, v__k];
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 24: {
                const __t0 = (v__args[0] = 26, v__args[1] = [25], v__args);
                const __t1 = [31, v__k];
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 25: {
                return (v__apply__scc_handleA_handleB)(v__k, [4, ""]);
              }
            }
          }
        }
      }
    }
  }
};

const v__scc_handleA_handleB = (v__args) => {
    return (v__cps__scc_handleA_handleB)(v__args, [28]);
};

const v_handleA = (v_step) => {
    return (v__scc_handleA_handleB)([26, v_step]);
};

const main = (v__let_12)((v_handleA)([22]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();