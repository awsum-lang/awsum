"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const v_spineLast = (v_t, v_lastV) => {
    while (true) {
      switch (v_t[0]) {
        case 24: {
          return v_lastV;
        }
        case 25: {
          v_lastV = v_t[2];
          v_t = v_t[1];
          continue;
        }
      }
    }
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

  const v_buildRight = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_acc];
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  const v_e = __s[1];
                  return [3, v_e];
                }
                case 4: {
                  const v_m = __s[1];
                  v_acc = [25, [24], v_n, v_acc];
                  v_n = v_m;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__scc__apply_mirror__cps_mirror = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 33: {
          const v__k = v__args[1];
          const v__x = v__args[2];
          switch (v__k[0]) {
            case 26: {
              return v__x;
            }
            case 28: {
              const v__pk_28 = v__k[1];
              v__args = (v__args[0] = 33, v__args[1] = v__pk_28, v__args[2] = (v__k[0] = 25, v__k[1] = v__k[2], v__k[2] = v__k[3], v__k[3] = v__x, v__k), v__args);
              continue;
            }
            case 27: {
              const v_l = v__k[2];
              v__args = (v__args[0] = 34, v__args[1] = v_l, v__args[2] = (v__k[0] = 28, v__k[2] = v__x, v__k), v__args);
              continue;
            }
          }
        }
        case 34: {
          const v_t = v__args[1];
          const v__k = v__args[2];
          switch (v_t[0]) {
            case 24: {
              v__args = (v__args[0] = 33, v__args[2] = v__args[1], v__args[1] = v__k, v__args);
              continue;
            }
            case 25: {
              v__args = (v__args[0] = 34, v__args[1] = v_t[3], v__args[2] = [
                27,
                v__k,
                v_t[1],
                v_t[2]
              ], v__args);
              continue;
            }
          }
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 29: {
          return v__x;
        }
        case 30: {
          const v__pk_30 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_30;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_0(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_0(v__k, [7, "UNDERFLOW", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [30, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 31: {
          return v__x;
        }
        case 32: {
          const v__pk_32 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_32;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_4(
            v__k,
            [
              7,
              String(
                v_spineLast(
                  v__scc__apply_mirror__cps_mirror([34, v_io[1], [26]]),
                  0 | 0
                )
              ),
              [5, [0]]
            ]
          );
        }
        case 6: {
          return v__apply__df_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [32, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl3_x = v_buildRight(100000 | 0, [24]);
  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl3_x[1]];
          }
          case 4: {
            return [5, v__inl3_x[1]];
          }
        }
      })(v__inl3_x),
      [31]
    ),
    [29]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
