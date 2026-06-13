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

  const v_go = (v_n, v_flag) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            switch (v_flag[0]) {
              case 1: {
                return "True";
              }
              case 2: {
                return "False";
              }
            }
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  return "underflow";
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  v_flag = (s => {
                    switch (s[0]) {
                      case 1: {
                        return [2];
                      }
                      case 2: {
                        return [1];
                      }
                    }
                  })(v_flag);
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const main = [7, v_go(3 | 0, [1]), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
