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
          const v__inl0_eff = __print(v_io[1]);
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
    let v__inl4_scrut;
    $join3: {
      switch (v_b[0]) {
        case 1: {
          const v__inl2_n = v_g(v_x);
          return [15, v__inl2_n, v__inl2_n];
        }
        case 2: {
          v__inl4_scrut = v_mk2(v_x);
          break $join3;
        }
      }
    }
    switch (v__inl4_scrut[0]) {
      case 24: {
        const v__inl1_n = v_g(v_x);
        return [15, v__inl1_n, v__inl1_n];
      }
      case 25: {
        return [15, v_x, v_x];
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 26: {
          return v__x;
        }
        case 27: {
          const v__pk_27 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_27;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_0(
            v__k,
            [
              7,
              String(
                (v__inl8__arg_0 =>
                  (s => {
                    switch (s[0]) {
                      case 3: {
                        return 0 | 0;
                      }
                      case 4: {
                        const v__inl10_s = s[1];
                        return v__inl10_s;
                      }
                    }
                  })(__addInt32(v__inl8__arg_0[1], v__inl8__arg_0[2])))(
                  v_run([2], 4 | 0)
                )
              ),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [27, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_andThenIO_0(
    [
      7,
      String(
        (v__inl13__arg_0 =>
          (s => {
            switch (s[0]) {
              case 3: {
                return 0 | 0;
              }
              case 4: {
                const v__inl12_s = s[1];
                return v__inl12_s;
              }
            }
          })(__addInt32(v__inl13__arg_0[1], v__inl13__arg_0[2])))(
          v_run([1], 3 | 0)
        )
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
