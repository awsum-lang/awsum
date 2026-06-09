"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = (x) => {
    return x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];
  };

  const __eqInt32 = (a, b) => {
    return a === b ? [1] : [2];
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

  const v_bBox = [24, [25]];

  const v__scc__apply1__lam_13_a_b = (v__args) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 26: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const __t0 = [27, v__arg0];
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 27: {
            const v_n = __s[1];
            const __t0 = (v__args[0] = 29, v__args[1] = v_n, v__args);
            v__args = __t0;
            continue;
          }
          case 28: {
            const v_n = __s[1];
            {
              const __s = __eqInt32(v_n, 0 | 0);
              switch (__s[0]) {
                case 1: {
                  return [4, 0 | 0];
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
                        {
                          const __s = v_bBox;
                          switch (__s[0]) {
                            case 24: {
                              const v_f = __s[1];
                              const __t0 = [26, v_f, v_m];
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
          case 29: {
            const v_n = __s[1];
            {
              const __s = __eqInt32(v_n, 0 | 0);
              switch (__s[0]) {
                case 1: {
                  return [4, 0 | 0];
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
                        const __t0 = (v__args[0] = 28, v__args[1] = v_m, v__args);
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

  const v_a = (v_n) => {
    return v__scc__apply1__lam_13_a_b([28, v_n]);
  };

  const main = ((s) => {
    switch (s[0]) {
      case 3: {
        const v__e = s[1];
        return [7, "underflow", [5, [0]]];
      }
      case 4: {
        const v_v = s[1];
        return [7, String(v_v), [5, [0]]];
      }
    }
  })(v_a(1000000 | 0));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
