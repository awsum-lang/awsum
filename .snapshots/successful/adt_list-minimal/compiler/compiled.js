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

const main = (v__let_8)((v_show)([19, "a", [19, "b", [19, "c", (v__lift_7)([20])]]]));

function v__lift_7(v___input){
    return (v__cps__lift_7)(v___input, [23]);
}

function v__cps__lift_7(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 19: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 24, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 20: {
          return (v__apply__lift_7)(v__k, [20]);
        }
      }
    }
  }
}

function v__apply__lift_7(v__k, v__x){
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
          const __t1 = (v__k[0] = 19, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__let_8(v_res){
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

function v__scc_show_showCons(v__args){
    return (v__cps__scc_show_showCons)(v__args, [25]);
}

function v__cps__scc_show_showCons(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 21: {
          const v_xs = __s[1];
          {
            const __s = v_xs;
            switch (__s[0]) {
              case 19: {
                const v_h = __s[1];
                const v_t = __s[2];
                const __t0 = [22, v_h, v_t];
                const __t1 = v__k;
                v__k = null;
                v__args = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 20: {
                return (v__apply__scc_show_showCons)(v__k, [4, ""]);
              }
            }
          }
        }
        case 22: {
          const v_h = __s[1];
          const v_t = __s[2];
          {
            const __s = __concat(v_h, ",");
            switch (__s[0]) {
              case 3: {
                const v__do_e_13_3 = __s[1];
                return (v__apply__scc_show_showCons)(v__k, [3, v__do_e_13_3]);
              }
              case 4: {
                const v_hc = __s[1];
                const __t0 = [21, v_t];
                const __t1 = (v__args[0] = 26, v__args[1] = v__k, v__args[2] = v_hc, v__args);
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v__apply__scc_show_showCons(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = __s[1];
          const v_hc = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_14_3 = __s[1];
                const __t0 = v__pk_26;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_14_3, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_26;
                const __t1 = __concat(v_hc, v_rest);
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

function v_show(v_xs){
    return (v__scc_show_showCons)([21, v_xs]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();