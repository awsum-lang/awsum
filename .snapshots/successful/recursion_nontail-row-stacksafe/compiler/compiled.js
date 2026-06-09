"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

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

  const v_runIO = v_io => {
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

  const v_extract = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1615808600: {
          const v__s = __s[1];
          return 0 | 0;
        }
        case 2711245919: {
          const v_n = __s[1];
          return v_n;
        }
      }
    }
  };

  const v_buildOnes = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_acc;
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  const v__e = __s[1];
                  return v_acc;
                }
                case 4: {
                  const v_m = __s[1];
                  const __t0 = v_m;
                  const __t1 = [14, [2711245919, 1 | 0], v_acc];
                  v_n = __t0;
                  v_acc = __t1;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_buildMixed = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [14, [1615808600, "s"], v_acc];
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  const v__e = __s[1];
                  return v_acc;
                }
                case 4: {
                  const v_m = __s[1];
                  const __t0 = v_m;
                  const __t1 = [14, [2711245919, 1 | 0], v_acc];
                  v_n = __t0;
                  v_acc = __t1;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__lam_16 = v__u => [7, " ", [5, [0]]];

  const v__lam_14 = v__u => [7, " ", [5, [0]]];

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

  const v_sumRow = v_xs => v__cps_sumRow(v_xs, [15]);

  const v__lam_15 = v__u =>
    [7, String(v_sumRow(v_buildMixed(3 | 0, [13]))), [5, [0]]];

  const v__apply_countRow = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 17: {
            return v__x;
          }
          case 18: {
            const v__pk_18 = __s[1];
            const __t0 = v__pk_18;
            const __t1 = [2711245919, v_extract(v__x)];
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps_countRow = (v_n, v__k) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v__apply_countRow(v__k, [2711245919, v_n]);
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  const v__e = __s[1];
                  return v__apply_countRow(v__k, [2711245919, v_n]);
                }
                case 4: {
                  const v_m = __s[1];
                  const __t0 = v_m;
                  const __t1 = [18, v__k];
                  v_n = __t0;
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

  const v_countRow = v_n => v__cps_countRow(v_n, [17]);

  const v__lam_13 = v__u =>
    [7, String(v_extract(v_countRow(1000000 | 0))), [5, [0]]];

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 23: {
            return v__x;
          }
          case 24: {
            const v__pk_24 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_24;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_8(v__k, v__lam_15(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 24, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_8 = v_io => v__cps__df_andThenIO_8(v_io, [23]);

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
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
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_4(v__k, v__lam_14(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 22, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_4 = v_io => v__cps__df_andThenIO_4(v_io, [21]);

  const v__apply__df_andThenIO_12 = (v__k, v__x) => {
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
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_12 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_12(v__k, v__lam_16(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 26, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_12 = v_io => v__cps__df_andThenIO_12(v_io, [25]);

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
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
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_0(v__k, v__lam_13(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 20, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_0 = v_io => v__cps__df_andThenIO_0(v_io, [19]);

  const main = v__df_andThenIO_0(
    v__df_andThenIO_4(
      v__df_andThenIO_8(
        v__df_andThenIO_12(
          [7, String(v_sumRow(v_buildOnes(1000000 | 0, [13]))), [5, [0]]]
        )
      )
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
