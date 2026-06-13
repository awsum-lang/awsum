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

  const v_buildLeft = (v_n, v_acc) => {
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
                  v_acc = [25, v_acc, [2711245919, 1 | 0], [24]];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__scc__apply_sumTree__cps_sumTree = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 29: {
          const v__k = v__args[1];
          const v__x = v__args[2];
          switch (v__k[0]) {
            case 26: {
              return v__x;
            }
            case 28: {
              const v__pk_28 = v__k[1];
              {
                const __s = __addInt32(v__k[2], v__x);
                switch (__s[0]) {
                  case 3: {
                    v__args = (v__args[0] = 29, v__args[1] = v__pk_28, v__args[2] = 0 | 0, v__args);
                    continue;
                  }
                  case 4: {
                    const v_s = __s[1];
                    {
                      const __s = __addInt32(v_s, v__k[3]);
                      switch (__s[0]) {
                        case 3: {
                          v__args = (v__args[0] = 29, v__args[1] = v__pk_28, v__args[2] = 0 | 0, v__args);
                          continue;
                        }
                        case 4: {
                          const v_s2 = __s[1];
                          v__args = (v__args[0] = 29, v__args[1] = v__pk_28, v__args[2] = v_s2, v__args);
                          continue;
                        }
                      }
                    }
                  }
                }
              }
            }
            case 27: {
              v__args = (v__args[0] = 30, v__args[1] = v__k[3], v__args[2] = [
                28,
                v__k[1],
                v__x,
                v__k[2]
              ], v__args);
              continue;
            }
          }
        }
        case 30: {
          const v_t = v__args[1];
          const v__k = v__args[2];
          switch (v_t[0]) {
            case 24: {
              v__args = (v__args[0] = 29, v__args[1] = v__args[2], v__args[2] = 0 | 0, v__args);
              continue;
            }
            case 25: {
              const v_l = v_t[1];
              const v_v = v_t[2];
              const v_r = v_t[3];
              v__args = (v__args[0] = 30, v__args[1] = v_l, v__args[2] = [
                27,
                v__k,
                v_v[1],
                v_r
              ], v__args);
              continue;
            }
          }
        }
      }
    }
  };

  const main = [
    7,
    String(
      v__scc__apply_sumTree__cps_sumTree(
        [30, v_buildLeft(200000 | 0, [24]), [26]]
      )
    ),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
