"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

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
          case 15: {
            return v__x;
          }
          case 16: {
            const v__pk_16 = __s[1];
            const v_n = __s[2];
            {
              const __s = __addInt32(v_n, v__x);
              switch (__s[0]) {
                case 3: {
                  const v__e = __s[1];
                  const __t0 = v__pk_16;
                  const __t1 = 0 | 0;
                  v__k = __t0;
                  v__x = __t1;
                  continue;
                }
                case 4: {
                  const v_r = __s[1];
                  const __t0 = v__pk_16;
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
          case 13: {
            return v__apply_sumRow(v__k, 0 | 0);
          }
          case 14: {
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
                  const __t1 = (v_xs[0] = 16, v_xs[1] = v__k, v_xs[2] = v_n, v_xs);
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
    return v__cps_sumRow(v_xs, [15]);
  };

  const v__apply__lift_18 = (v__k, v__x) => {
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

  const v__cps__lift_18 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 13: {
            return v__apply__lift_18(v__k, [13]);
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

  const v__lift_18 = (v___input) => {
    return v__cps__lift_18(v___input, [17]);
  };

  const v_mixed = [
    14,
    [2711245919, 1 | 0],
    [
      14,
      [1615808600, "x"],
      [
        14,
        [2711245919, 2 | 0],
        [14, [1615808600, "y"], [14, [2711245919, 3 | 0], v__lift_18([13])]]
      ]
    ]
  ];

  const main = [7, String(v_sumRow(v_mixed)), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
