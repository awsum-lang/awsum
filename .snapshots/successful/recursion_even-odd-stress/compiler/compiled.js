"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_showUnderflowError = v__wild0 => "UnderflowError";

  const v_showBool = v_b => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 1: {
          return "True";
        }
        case 2: {
          return "False";
        }
      }
    }
  };

  const v_showResult = v_r => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return __concat("left: ", v_showUnderflowError(v_e));
        }
        case 4: {
          const v_b = __s[1];
          return __concat("right: ", v_showBool(v_b));
        }
      }
    }
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

  const v__scc_evenInt_oddInt = v__args => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 8: {
            const v_n = __s[1];
            {
              const __s = __eqInt32(v_n, 0 | 0);
              switch (__s[0]) {
                case 1: {
                  return [4, [1]];
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
                        const __t0 = (v__args[0] = 9, v__args[1] = v_m, v__args);
                        v__args = __t0;
                        continue;
                      }
                    }
                  }
                }
              }
            }
          }
          case 9: {
            const v_n = __s[1];
            {
              const __s = __eqInt32(v_n, 0 | 0);
              switch (__s[0]) {
                case 1: {
                  return [4, [2]];
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
                        const __t0 = (v__args[0] = 8, v__args[1] = v_m, v__args);
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

  const v_evenInt = v_n => v__scc_evenInt_oddInt([8, v_n]);

  const v__let_13 = v_res => {
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

  const main = v__let_13(v_showResult(v_evenInt(1000000 | 0)));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
