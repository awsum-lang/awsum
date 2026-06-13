"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

  const __addUInt32 = (a, b) => {
    const s = a + b;
    return s > 4294967295 ? [3, [18]] : [4, s >>> 0];
  };

  const __subUInt32 = (a, b) => {
    const d = a - b;
    return d < 0 ? [3, [17]] : [4, d >>> 0];
  };

  const v_wrap = (v_n, v_d, v_acc) => {
    while (true) {
      {
        const __s = __eqUInt32(v_n, 0 >>> 0);
        switch (__s[0]) {
          case 1: {
            switch (v_acc[0]) {
              case 13: {
                return "none";
              }
              case 14: {
                return String(v_acc[1]);
              }
            }
          }
          case 2: {
            {
              const __s = __subUInt32(v_n, 1 >>> 0);
              switch (__s[0]) {
                case 3: {
                  return "E";
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  v_acc = [14, v_d, v_acc];
                  v_d = v_m;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_swap = (v_n, v_a, v_b) => {
    while (true) {
      {
        const __s = __eqUInt32(v_n, 0 >>> 0);
        switch (__s[0]) {
          case 1: {
            return String(v_a);
          }
          case 2: {
            {
              const __s = __subUInt32(v_n, 1 >>> 0);
              switch (__s[0]) {
                case 3: {
                  return "E";
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  const __t1 = v_b;
                  const __t2 = v_a;
                  v_a = __t1;
                  v_b = __t2;
                  continue;
                }
              }
            }
          }
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

  const v_fib = (v_n, v_a, v_b) => {
    while (true) {
      {
        const __s = __eqUInt32(v_n, 0 >>> 0);
        switch (__s[0]) {
          case 1: {
            return String(v_a);
          }
          case 2: {
            {
              const __s = __addUInt32(v_a, v_b);
              switch (__s[0]) {
                case 3: {
                  return "OVERFLOW";
                }
                case 4: {
                  const v_s = __s[1];
                  {
                    const __s = __subUInt32(v_n, 1 >>> 0);
                    switch (__s[0]) {
                      case 3: {
                        return "E";
                      }
                      case 4: {
                        const v_m = __s[1];
                        v_n = v_m;
                        v_a = v_b;
                        v_b = v_s;
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

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "TOO_LONG", [5, [0]]];
      }
      case 4: {
        const v_p1 = s[1];
        {
          const __s = __concat(
            v_p1,
            v_wrap(4 >>> 0, 1 >>> 0, [14, 1 >>> 0, [13]])
          );
          switch (__s[0]) {
            case 3: {
              return [7, "TOO_LONG", [5, [0]]];
            }
            case 4: {
              const v_p2 = __s[1];
              {
                const __s = __concat(v_p2, "|");
                switch (__s[0]) {
                  case 3: {
                    return [7, "TOO_LONG", [5, [0]]];
                  }
                  case 4: {
                    const v_p3 = __s[1];
                    {
                      const __s = __concat(
                        v_p3,
                        v_fib(40 >>> 0, 0 >>> 0, 1 >>> 0)
                      );
                      switch (__s[0]) {
                        case 3: {
                          return [7, "TOO_LONG", [5, [0]]];
                        }
                        case 4: {
                          const v_out = __s[1];
                          return [7, v_out, [5, [0]]];
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
  })(__concat(v_swap(5 >>> 0, 7 >>> 0, 9 >>> 0), "|"));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
