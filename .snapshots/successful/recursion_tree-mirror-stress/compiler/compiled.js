"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const v_spineLast = (v_t, v_lastV) => {
    while (true) {
      switch (v_t[0]) {
        case 24: {
          return v_lastV;
        }
        case 25: {
          v_lastV = v_t[2];
          v_t = v_t[1];
          continue;
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
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_buildRight = (v_n, v_acc) => {
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
                  v_acc = [25, [24], v_n, v_acc];
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

  const v_$scc$$apply$mirror__$cps$mirror = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 33: {
          const v_$k = v_$args[1];
          const v_$x = v_$args[2];
          switch (v_$k[0]) {
            case 26: {
              return v_$x;
            }
            case 28: {
              const v_$pk__28 = v_$k[1];
              v_$args = (v_$args[0] = 33, v_$args[1] = v_$pk__28, v_$args[2] = (v_$k[0] = 25, v_$k[1] = v_$k[2], v_$k[2] = v_$k[3], v_$k[3] = v_$x, v_$k), v_$args);
              continue;
            }
            case 27: {
              const v_l = v_$k[2];
              v_$args = (v_$args[0] = 34, v_$args[1] = v_l, v_$args[2] = (v_$k[0] = 28, v_$k[2] = v_$x, v_$k), v_$args);
              continue;
            }
          }
        }
        case 34: {
          const v_t = v_$args[1];
          const v_$k = v_$args[2];
          switch (v_t[0]) {
            case 24: {
              v_$args = (v_$args[0] = 33, v_$args[2] = v_$args[1], v_$args[1] = v_$k, v_$args);
              continue;
            }
            case 25: {
              v_$args = (v_$args[0] = 34, v_$args[1] = v_t[3], v_$args[2] = [
                27,
                v_$k,
                v_t[1],
                v_t[2]
              ], v_$args);
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
        case 29: {
          return v_$x;
        }
        case 30: {
          const v_$pk__30 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__30;
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
          v_$k = [30, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 31: {
          return v_$x;
        }
        case 32: {
          const v_$pk__32 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__32;
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
                v_spineLast(
                  v_$scc$$apply$mirror__$cps$mirror([34, v_io[1], [26]]),
                  0 | 0
                )
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
          v_$k = [32, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl3$x = v_buildRight(100000 | 0, [24]);
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl3$x[1]];
          }
          case 4: {
            return [5, v_$inl3$x[1]];
          }
        }
      })(v_$inl3$x),
      [31]
    ),
    [29]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
