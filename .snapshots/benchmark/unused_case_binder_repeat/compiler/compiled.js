"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

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

  const v_length = (v_xs, v_acc) => {
    while (true) {
      switch (v_xs[0]) {
        case 24: {
          return v_acc;
        }
        case 25: {
          {
            const __s = __succInt32(v_acc);
            switch (__s[0]) {
              case 3: {
                return v_acc;
              }
              case 4: {
                const v_a = __s[1];
                v_xs = v_xs[2];
                v_acc = v_a;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v_build = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, v_zero);
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
                  v_acc = [25, v_n, v_acc];
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

  const v_runN = (v_iters, v_listLen, v_accSum) => {
    while (true) {
      {
        const __s = __eqInt32(v_iters, v_zero);
        switch (__s[0]) {
          case 1: {
            return v_accSum;
          }
          case 2: {
            {
              const __s = __predInt32(v_iters);
              switch (__s[0]) {
                case 3: {
                  return v_accSum;
                }
                case 4: {
                  const v_i = __s[1];
                  {
                    const __s = __addInt32(
                      v_accSum,
                      v_length(v_build(v_listLen, [24]), v_zero)
                    );
                    switch (__s[0]) {
                      case 3: {
                        return v_accSum;
                      }
                      case 4: {
                        const v_s = __s[1];
                        v_iters = v_i;
                        v_accSum = v_s;
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

  const main = [7, String(v_runN(1000 | 0, 10000 | 0, v_zero)), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
