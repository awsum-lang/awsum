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
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$scc$$apply1__$lam$13__a__b = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 26: {
          v_$args = [27, v_$args[2]];
          continue;
        }
        case 27: {
          v_$args = (v_$args[0] = 29, v_$args);
          continue;
        }
        case 28: {
          const v_n = v_$args[1];
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
                      v_$args = [26, [25], v_m];
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 29: {
          const v_n = v_$args[1];
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
                      v_$args = (v_$args[0] = 28, v_$args[1] = v_m, v_$args);
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

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$0(v_$k, [7, "underflow", [5, [0]]]);
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

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 32: {
          return v_$x;
        }
        case 33: {
          const v_$pk__33 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__33;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(v_$k, [7, String(v_io[1]), [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [33, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl3$x = v_$scc$$apply1__$lam$13__a__b([28, 1000000 | 0]);
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
      [32]
    ),
    [30]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
