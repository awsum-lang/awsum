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
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
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
                  return v_acc;
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  v_acc = [14, [2711245919, 1 | 0], v_acc];
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
                  return v_acc;
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  v_acc = [14, [2711245919, 1 | 0], v_acc];
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
      switch (v__k[0]) {
        case 15: {
          return v__x;
        }
        case 16: {
          const v__pk_16 = v__k[1];
          {
            const __s = __addInt32(v__k[2], v__x);
            switch (__s[0]) {
              case 3: {
                v__k = v__pk_16;
                v__x = 0 | 0;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                v__k = v__pk_16;
                v__x = v_r;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v__cps_sumRow = (v_xs, v__k) => {
    while (true) {
      switch (v_xs[0]) {
        case 13: {
          return v__apply_sumRow(v__k, 0 | 0);
        }
        case 14: {
          const v_h = v_xs[1];
          const v_t = v_xs[2];
          switch (v_h[0]) {
            case 1615808600: {
              v_xs = v_t;
              continue;
            }
            case 2711245919: {
              v__k = [16, v__k, v_h[1]];
              v_xs = v_t;
              continue;
            }
          }
        }
      }
    }
  };

  const v__apply_countRow = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 17: {
          return v__x;
        }
        case 18: {
          v__k = v__k[1];
          v__x = [
            2711245919,
            (s => {
              switch (s[0]) {
                case 1615808600: {
                  return 0 | 0;
                }
                case 2711245919: {
                  return v__x[1];
                }
              }
            })(v__x)
          ];
          continue;
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
                  return v__apply_countRow(v__k, [2711245919, v_n]);
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  v__k = [18, v__k];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 23: {
          return v__x;
        }
        case 24: {
          const v__pk_24 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_24;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_8(
            v__k,
            [
              7,
              String(v__cps_sumRow(v_buildMixed(3 | 0, [13]), [15])),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [24, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 21: {
          return v__x;
        }
        case 22: {
          const v__pk_22 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_22;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_4(v__k, [7, " ", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [22, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_12 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_26;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_12 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_12(v__k, [7, " ", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [26, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 19: {
          return v__x;
        }
        case 20: {
          const v__pk_20 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_20;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl6_x = v__cps_countRow(1000000 | 0, [17]);
          return v__apply__df_andThenIO_0(
            v__k,
            [
              7,
              String(
                (s => {
                  switch (s[0]) {
                    case 1615808600: {
                      return 0 | 0;
                    }
                    case 2711245919: {
                      return v__inl6_x[1];
                    }
                  }
                })(v__inl6_x)
              ),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [20, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_andThenIO_0(
    v__cps__df_andThenIO_4(
      v__cps__df_andThenIO_8(
        v__cps__df_andThenIO_12(
          [
            7,
            String(v__cps_sumRow(v_buildOnes(1000000 | 0, [13]), [15])),
            [5, [0]]
          ],
          [25]
        ),
        [23]
      ),
      [21]
    ),
    [19]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
