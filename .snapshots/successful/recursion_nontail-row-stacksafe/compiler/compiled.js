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

  const v_buildOnes = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
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
                  v_n = v_m;
                  v_acc = [14, [2711245919, 1 | 0], v_acc];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_buildMixed = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [14, [1615808600, "s"], v_acc];
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
                  v_n = v_m;
                  v_acc = [14, [2711245919, 1 | 0], v_acc];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$apply$sumRow = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 15: {
          return v_$x;
        }
        case 16: {
          const v_$pk__16 = v_$k[1];
          {
            const __s = __addInt32(v_$k[2], v_$x);
            switch (__s[0]) {
              case 3: {
                v_$k = v_$pk__16;
                v_$x = 0 | 0;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                v_$k = v_$pk__16;
                v_$x = v_r;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v_$cps$sumRow = (v_xs, v_$k) => {
    while (true) {
      switch (v_xs[0]) {
        case 13: {
          return v_$apply$sumRow(v_$k, 0 | 0);
        }
        case 14: {
          const v_h = v_xs[1];
          const v_t = v_xs[2];
          switch (v_h[0]) {
            case 1615808600: {
              v_xs = v_t;
              continue;
            }
            case 2711245919: {
              v_$k = [16, v_$k, v_h[1]];
              v_xs = v_t;
              continue;
            }
          }
        }
      }
    }
  };

  const v_$apply$countRow = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 17: {
          return v_$x;
        }
        case 18: {
          v_$k = v_$k[1];
          v_$x = [
            2711245919,
            (s => {
              switch (s[0]) {
                case 1615808600: {
                  return 0 | 0;
                }
                case 2711245919: {
                  return v_$x[1];
                }
              }
            })(v_$x)
          ];
          continue;
        }
      }
    }
  };

  const v_$cps$countRow = (v_n, v_$k) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_$apply$countRow(v_$k, [2711245919, v_n]);
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  return v_$apply$countRow(v_$k, [2711245919, v_n]);
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  v_$k = [18, v_$k];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$8 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 23: {
          return v_$x;
        }
        case 24: {
          const v_$pk__24 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__24;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$8(
            v_$k,
            [
              7,
              String(v_$cps$sumRow(v_buildMixed(3 | 0, [13]), [15])),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [24, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 21: {
          return v_$x;
        }
        case 22: {
          const v_$pk__22 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__22;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(v_$k, [7, " ", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [22, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$12 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 25: {
          return v_$x;
        }
        case 26: {
          const v_$pk__26 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__26;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$12 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$12(v_$k, [7, " ", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [26, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 19: {
          return v_$x;
        }
        case 20: {
          const v_$pk__20 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__20;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl6$x = v_$cps$countRow(1000000 | 0, [17]);
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [
              7,
              String(
                (s => {
                  switch (s[0]) {
                    case 1615808600: {
                      return 0 | 0;
                    }
                    case 2711245919: {
                      return v_$inl6$x[1];
                    }
                  }
                })(v_$inl6$x)
              ),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [20, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$andThenIO$0(
    v_$cps$$df$andThenIO$4(
      v_$cps$$df$andThenIO$8(
        v_$cps$$df$andThenIO$12(
          [
            7,
            String(v_$cps$sumRow(v_buildOnes(1000000 | 0, [13]), [15])),
            [5, [0]]
          ],
          [25]
        ),
        [23]
      ),
      [21]
    ),
    [19]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
