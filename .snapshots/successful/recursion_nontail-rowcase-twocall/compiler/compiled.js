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
                  const v__e = __s[1];
                  return v_acc;
                }
                case 4: {
                  const v_m = __s[1];
                  const __t0 = v_m;
                  const __t1 = [25, v_acc, [2711245919, 1 | 0], [24]];
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

  const v__scc__apply_sumTree__cps_sumTree = v__args => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 29: {
            const v__k = __s[1];
            const v__x = __s[2];
            {
              const __s = v__k;
              switch (__s[0]) {
                case 26: {
                  return v__x;
                }
                case 28: {
                  const v__pk_28 = __s[1];
                  const v__rcv_0 = __s[2];
                  const v_n = __s[3];
                  {
                    const __s = __addInt32(v__rcv_0, v__x);
                    switch (__s[0]) {
                      case 3: {
                        const v__e = __s[1];
                        const __t0 = (v__args[0] = 29, v__args[1] = v__pk_28, v__args[2] = 0 | 0, v__args);
                        v__args = __t0;
                        continue;
                      }
                      case 4: {
                        const v_s = __s[1];
                        {
                          const __s = __addInt32(v_s, v_n);
                          switch (__s[0]) {
                            case 3: {
                              const v__e = __s[1];
                              const __t0 = (v__args[0] = 29, v__args[1] = v__pk_28, v__args[2] = 0 | 0, v__args);
                              v__args = __t0;
                              continue;
                            }
                            case 4: {
                              const v_s2 = __s[1];
                              const __t0 = (v__args[0] = 29, v__args[1] = v__pk_28, v__args[2] = v_s2, v__args);
                              v__args = __t0;
                              continue;
                            }
                          }
                        }
                      }
                    }
                  }
                }
                case 27: {
                  const v__pk_27 = __s[1];
                  const v_n = __s[2];
                  const v_r = __s[3];
                  const __t0 = (v__args[0] = 30, v__args[1] = v_r, v__args[2] = [
                    28,
                    v__pk_27,
                    v__x,
                    v_n
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 30: {
            const v_t = __s[1];
            const v__k = __s[2];
            {
              const __s = v_t;
              switch (__s[0]) {
                case 24: {
                  const __t0 = (v__args[0] = 29, v__args[1] = v__k, v__args[2] = 0 | 0, v__args);
                  v__args = __t0;
                  continue;
                }
                case 25: {
                  const v_l = __s[1];
                  const v_v = __s[2];
                  const v_r = __s[3];
                  {
                    const __s = v_v;
                    switch (__s[0]) {
                      case 2711245919: {
                        const v_n = __s[1];
                        const __t0 = (v__args[0] = 30, v__args[1] = v_l, v__args[2] = [
                          27,
                          v__k,
                          v_n,
                          v_r
                        ], v__args);
                        v__args = __t0;
                        continue;
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  const v__cps_sumTree = (v_t, v__k) =>
    v__scc__apply_sumTree__cps_sumTree([30, v_t, v__k]);

  const v_sumTree = v_t => v__cps_sumTree(v_t, [26]);

  const main = [7, String(v_sumTree(v_buildLeft(200000 | 0, [24]))), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
