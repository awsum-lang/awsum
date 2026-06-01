"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [3, [882564211, [17]]]; if (s < -2147483648) return [3, [3768445577, [16]]]; return [4, s|0]; }

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

const v__apply_sumRow = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 14: {
          return v__x;
        }
        case 15: {
          const v__pk_15 = __s[1];
          const v_n = __s[2];
          {
            const __s = __addInt32(v_n, v__x);
            switch (__s[0]) {
              case 3: {
                const v__e = __s[1];
                const __t0 = v__pk_15;
                const __t1 = (0|0);
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                const __t0 = v__pk_15;
                const __t1 = v_r;
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

const v__cps_sumRow = (v_xs, v__k) => {
  while (true) {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 12: {
          return (v__apply_sumRow)(v__k, (0|0));
        }
        case 13: {
          const v_h = __s[1];
          const v_t = __s[2];
          {
            const __s = v_h;
            switch (__s[0]) {
              case 1615808600: {
                const v__s = __s[1];
                const __t0 = v_t;
                const __t1 = v__k;
                v_xs = __t0;
                v__k = __t1;
                continue;
              }
              case 2711245919: {
                const v_n = __s[1];
                const __t0 = v_t;
                const __t1 = (v_xs[0] = 15, v_xs[1] = v__k, v_xs[2] = v_n, v_xs);
                v_xs = __t0;
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

const v_sumRow = (v_xs) => {
    return (v__cps_sumRow)(v_xs, [14]);
};

const v__apply__lift_15 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 16: {
          return v__x;
        }
        case 17: {
          const v__pk_17 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_17;
          const __t1 = (v__k[0] = 13, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_15 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 12: {
          return (v__apply__lift_15)(v__k, [12]);
        }
        case 13: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 17, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__lift_15 = (v___input) => {
    return (v__cps__lift_15)(v___input, [16]);
};

const v_mixed = [13, [2711245919, (1|0)], [13, [1615808600, "x"], [13, [2711245919, (2|0)], [13, [1615808600, "y"], [13, [2711245919, (3|0)], (v__lift_15)([12])]]]]];

const main = [7, String((v_sumRow)(v_mixed)), [5, [0]]];

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();