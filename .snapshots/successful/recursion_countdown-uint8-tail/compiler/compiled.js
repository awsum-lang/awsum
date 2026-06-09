"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predUInt8 = (x) => {
    return x === 0 ? [3, [17]] : [4, x - 1 & 0xFF];
  };

  const __eqUInt8 = (a, b) => {
    return a === b ? [1] : [2];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const v_showUnderflowError = (v__wild0) => {
    return "UnderflowError";
  };

  const v_showResult = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 589989748: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 19: {
                      return [4, "STRING_TOO_LONG"];
                    }
                  }
                }
              }
              case 3768445577: {
                const v_u = __s[1];
                return __concat("left: ", v_showUnderflowError(v_u));
              }
            }
          }
        }
        case 4: {
          const v_s = __s[1];
          return __concat("right: ", v_s);
        }
      }
    }
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

  const v__lift_13 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [589989748, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v_countDown = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqUInt8(v_n, 0 & 0xFF);
        switch (__s[0]) {
          case 1: {
            return v__lift_13(__concat(v_acc, String(v_n)));
          }
          case 2: {
            {
              const __s = __predUInt8(v_n);
              switch (__s[0]) {
                case 3: {
                  const v_e = __s[1];
                  return [3, [3768445577, v_e]];
                }
                case 4: {
                  const v_m = __s[1];
                  {
                    const __s = __concat(v_acc, String(v_n));
                    switch (__s[0]) {
                      case 3: {
                        const v_e = __s[1];
                        return [3, [589989748, v_e]];
                      }
                      case 4: {
                        const v_s0 = __s[1];
                        {
                          const __s = __concat(v_s0, ",");
                          switch (__s[0]) {
                            case 3: {
                              const v_e = __s[1];
                              return [3, [589989748, v_e]];
                            }
                            case 4: {
                              const v_s1 = __s[1];
                              const __t0 = v_m;
                              const __t1 = v_s1;
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
              }
            }
          }
        }
      }
    }
  };

  const v__let_14 = (v_res) => {
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

  const main = v__let_14(v_showResult(v_countDown(255 & 0xFF, "")));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
