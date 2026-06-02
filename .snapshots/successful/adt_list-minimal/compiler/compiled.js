"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [19]] : [4, a + b]; }

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

const v__let_24 = (v_res) => {
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

const v__apply__scc_show_showCons = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 19: {
          return v__x;
        }
        case 20: {
          const v__pk_20 = __s[1];
          const v_hc = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                const __t0 = v__pk_20;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_0, v__x);
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_20;
                const __t1 = __concat(v_hc, v_rest);
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

const v__cps__scc_show_showCons = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 15: {
          const v_xs = __s[1];
          {
            const __s = v_xs;
            switch (__s[0]) {
              case 13: {
                return (v__apply__scc_show_showCons)(v__k, [4, ""]);
              }
              case 14: {
                const v_h = __s[1];
                const v_t = __s[2];
                const __t0 = [16, v_h, v_t];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 16: {
          const v_h = __s[1];
          const v_t = __s[2];
          {
            const __s = __concat(v_h, ",");
            switch (__s[0]) {
              case 3: {
                const v__do_e_1 = __s[1];
                return (v__apply__scc_show_showCons)(v__k, [3, v__do_e_1]);
              }
              case 4: {
                const v_hc = __s[1];
                const __t0 = [15, v_t];
                const __t1 = (v__args[0] = 20, v__args[1] = v__k, v__args[2] = v_hc, v__args);
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
};

const v__scc_show_showCons = (v__args) => {
    return (v__cps__scc_show_showCons)(v__args, [19]);
};

const v_show = (v_xs) => {
    return (v__scc_show_showCons)([15, v_xs]);
};

const v__apply__lift_23 = (v__k, v__x) => {
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
          const __t1 = (v__k[0] = 14, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_23 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 13: {
          return (v__apply__lift_23)(v__k, [13]);
        }
        case 14: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 18, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__lift_23 = (v___input) => {
    return (v__cps__lift_23)(v___input, [17]);
};

const main = (v__let_24)((v_show)([14, "a", [14, "b", [14, "c", (v__lift_23)([13])]]]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();