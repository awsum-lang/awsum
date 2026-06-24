"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const __subInt32 = (a, b) => {
    const r = a - b;
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

  const v_mk2 = v_n => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [25];
          }
          case 2: {
            {
              const __s = __subInt32(v_n, 1 | 0);
              switch (__s[0]) {
                case 3: {
                  return [24];
                }
                case 4: {
                  const v_m = __s[1];
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

  const v_g = v_n => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return 7 | 0;
          }
          case 2: {
            {
              const __s = __subInt32(v_n, 1 | 0);
              switch (__s[0]) {
                case 3: {
                  return 7 | 0;
                }
                case 4: {
                  const v_m = __s[1];
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

  const v_run = (v_b, v_x) => {
    let v_$inl4$scrut;
    $join3: {
      switch (v_b[0]) {
        case 1: {
          const v_$inl2$n = v_g(v_x);
          return [15, v_$inl2$n, v_$inl2$n];
        }
        case 2: {
          v_$inl4$scrut = v_mk2(v_x);
          break $join3;
        }
      }
    }
    switch (v_$inl4$scrut[0]) {
      case 24: {
        const v_$inl1$n = v_g(v_x);
        return [15, v_$inl1$n, v_$inl1$n];
      }
      case 25: {
        return [15, v_x, v_x];
      }
    }
  };

  const v_$apply$$df$andThenIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 26: {
          return v_$x;
        }
        case 27: {
          const v_$pk__27 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__27;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl8$$arg__0 = v_run([2], 4 | 0);
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [
              7,
              String(
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return 0 | 0;
                    }
                    case 4: {
                      const v_$inl10$s = s[1];
                      return v_$inl10$s;
                    }
                  }
                })(__addInt32(v_$inl8$$arg__0[1], v_$inl8$$arg__0[2]))
              ),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [27, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl13$$arg__0 = v_run([1], 3 | 0);
  const main = v_$cps$$df$andThenIO$0(
    [
      7,
      String(
        (s => {
          switch (s[0]) {
            case 3: {
              return 0 | 0;
            }
            case 4: {
              const v_$inl12$s = s[1];
              return v_$inl12$s;
            }
          }
        })(__addInt32(v_$inl13$$arg__0[1], v_$inl13$$arg__0[2]))
      ),
      [5, [0]]
    ],
    [26]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
