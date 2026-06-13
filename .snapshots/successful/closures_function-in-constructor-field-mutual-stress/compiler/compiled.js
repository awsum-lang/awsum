"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

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

  const v__scc__apply1__lam_13_a_b = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 26: {
          v__args = [27, v__args[2]];
          continue;
        }
        case 27: {
          v__args = (v__args[0] = 29, v__args);
          continue;
        }
        case 28: {
          const v_n = v__args[1];
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
                      v__args = [26, [25], v_m];
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 29: {
          const v_n = v__args[1];
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
                      v__args = (v__args[0] = 28, v__args[1] = v_m, v__args);
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

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "underflow", [5, [0]]];
      }
      case 4: {
        const v_v = s[1];
        return [7, String(v_v), [5, [0]]];
      }
    }
  })(v__scc__apply1__lam_13_a_b([28, 1000000 | 0]));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
