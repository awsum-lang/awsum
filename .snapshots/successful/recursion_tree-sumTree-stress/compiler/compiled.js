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

  const v_buildLeft = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_acc];
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
                  v_n = v_m;
                  v_acc = [25, v_acc, 1 | 0, [24]];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$scc$$apply$sumTree__$cps$sumTree = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 32: {
          const v_$k = v_$args[1];
          const v_$x = v_$args[2];
          switch (v_$k[0]) {
            case 26: {
              return v_$x;
            }
            case 27: {
              v_$args = [33, v_$k[2], v_$x, v_$k[1]];
              continue;
            }
          }
        }
        case 33: {
          const v_t = v_$args[1];
          const v_acc = v_$args[2];
          const v_$k = v_$args[3];
          switch (v_t[0]) {
            case 24: {
              v_$args = [32, v_$k, v_acc];
              continue;
            }
            case 25: {
              const v_l = v_t[1];
              const v_v = v_t[2];
              const v_r = v_t[3];
              v_$args = [
                33,
                v_l,
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return 0 | 0;
                    }
                    case 4: {
                      const v_$inl2$v = s[1];
                      return v_$inl2$v;
                    }
                  }
                })(__addInt32(v_acc, v_v)),
                [27, v_$k, v_r]
              ];
              continue;
            }
          }
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 28: {
          return v_$x;
        }
        case 29: {
          const v_$pk__29 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__29;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$0(v_$k, [7, "UNDERFLOW", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [29, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 30: {
          return v_$x;
        }
        case 31: {
          const v_$pk__31 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__31;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(
            v_$k,
            [
              7,
              String(
                v_$scc$$apply$sumTree__$cps$sumTree([33, v_io[1], 0 | 0, [26]])
              ),
              [5, [0]]
            ]
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [31, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl5$x = v_buildLeft(100000 | 0, [24]);
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl5$x[1]];
          }
          case 4: {
            return [5, v_$inl5$x[1]];
          }
        }
      })(v_$inl5$x),
      [30]
    ),
    [28]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
