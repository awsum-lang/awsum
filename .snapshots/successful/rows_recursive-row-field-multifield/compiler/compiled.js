"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const v_v = [
    25,
    [1907350996, [25, [1907350996, [24, 1 | 0]], [1907350996, [24, 2 | 0]]]],
    [1907350996, [24, 3 | 0]]
  ];

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

  const v_$scc$$apply$$scc$sumSide__sumT__$cps$$scc$sumSide__sumT = v_$args$1 => {
    while (true) {
      switch (v_$args$1[0]) {
        case 31: {
          const v_$k = v_$args$1[1];
          const v_$x = v_$args$1[2];
          switch (v_$k[0]) {
            case 28: {
              return v_$x;
            }
            case 30: {
              const v_$rcv__0 = v_$k[2];
              {
                const __s = __addInt32(v_$rcv__0, v_$x);
                switch (__s[0]) {
                  case 3: {
                    v_$args$1 = (v_$k[0] = 31, v_$k[2] = 0 | 0, v_$k);
                    continue;
                  }
                  case 4: {
                    const v_s = __s[1];
                    v_$args$1 = (v_$k[0] = 31, v_$k[2] = v_s, v_$k);
                    continue;
                  }
                }
              }
            }
            case 29: {
              const v_r = v_$k[2];
              v_$args$1 = (v_$args$1[0] = 32, v_$args$1[1] = [
                26,
                v_r
              ], v_$args$1[2] = (v_$k[0] = 30, v_$k[2] = v_$x, v_$k), v_$args$1);
              continue;
            }
          }
        }
        case 32: {
          const v_$args = v_$args$1[1];
          switch (v_$args[0]) {
            case 26: {
              const v_x = v_$args[1];
              v_$args$1 = (v_$args$1[0] = 32, v_$args$1[1] = (v_$args[0] = 27, v_$args[1] = v_x[1], v_$args), v_$args$1);
              continue;
            }
            case 27: {
              const v_t = v_$args[1];
              switch (v_t[0]) {
                case 24: {
                  v_$args$1 = (v_$args$1[0] = 31, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_t[1], v_$args$1);
                  continue;
                }
                case 25: {
                  v_$args$1 = [
                    32,
                    (v_$args[0] = 26, v_$args[1] = v_t[1], v_$args),
                    (v_$args$1[0] = 29, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_t[2], v_$args$1)
                  ];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const main = [
    7,
    String(
      v_$scc$$apply$$scc$sumSide__sumT__$cps$$scc$sumSide__sumT(
        [32, [27, v_v], [28]]
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
