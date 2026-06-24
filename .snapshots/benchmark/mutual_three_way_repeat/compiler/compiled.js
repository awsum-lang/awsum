"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const v_zero = 0 | 0;

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$scc$stepA__stepB__stepC = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 8: {
          const v_n = v_$args[1];
          {
            const __s = __eqInt32(v_n, v_zero);
            switch (__s[0]) {
              case 1: {
                return [4, v_zero];
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
                      v_$args = (v_$args[0] = 9, v_$args[1] = v_m, v_$args);
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 9: {
          const v_n = v_$args[1];
          {
            const __s = __eqInt32(v_n, v_zero);
            switch (__s[0]) {
              case 1: {
                return [4, v_zero];
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
                      v_$args = (v_$args[0] = 10, v_$args[1] = v_m, v_$args);
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 10: {
          const v_n = v_$args[1];
          {
            const __s = __eqInt32(v_n, v_zero);
            switch (__s[0]) {
              case 1: {
                return [4, v_zero];
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
                      v_$args = (v_$args[0] = 8, v_$args[1] = v_m, v_$args);
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
  };

  const v_outerLoop = v_k => {
    while (true) {
      {
        const __s = __eqInt32(v_k, v_zero);
        switch (__s[0]) {
          case 1: {
            return [4, v_zero];
          }
          case 2: {
            {
              const __s = __predInt32(v_k);
              switch (__s[0]) {
                case 3: {
                  const v_e = __s[1];
                  return [3, v_e];
                }
                case 4: {
                  const v_m = __s[1];
                  {
                    const __s = v_$scc$stepA__stepB__stepC([8, 1000000 | 0]);
                    switch (__s[0]) {
                      case 3: {
                        const v_e = __s[1];
                        return [3, v_e];
                      }
                      case 4: {
                        v_k = v_m;
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
        return [7, "UNDERFLOW", [5, [0]]];
      }
      case 4: {
        return [7, "ok", [5, [0]]];
      }
    }
  })(v_outerLoop(100 | 0));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
