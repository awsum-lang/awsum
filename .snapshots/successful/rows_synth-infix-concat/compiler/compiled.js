"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v_double = (v_n, v_s) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_s];
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  const v_ue = __s[1];
                  return [3, [3768445577, v_ue]];
                }
                case 4: {
                  const v_m = __s[1];
                  {
                    const __s = __concat(v_s, v_s);
                    switch (__s[0]) {
                      case 3: {
                        const v_se = __s[1];
                        return [3, [589989748, v_se]];
                      }
                      case 4: {
                        const v_s2 = __s[1];
                        v_n = v_m;
                        v_s = v_s2;
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

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 8: {
          return v__x;
        }
        case 9: {
          const v__pk_9 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_9;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_0(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_0(
            v__k,
            (s => {
              switch (s[0]) {
                case 589989748: {
                  return [7, "string-too-long", [5, [0]]];
                }
                case 3768445577: {
                  return [7, "underflow", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [9, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 10: {
          return v__x;
        }
        case 11: {
          const v__pk_11 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_11;
          continue;
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_0_andThenIO_4(
            v__k,
            [7, "done", [5, [0]]]
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [11, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl5_x = v_double(24 | 0, "0123456789abcdef");
  const main = v__cps__df_handleErrorIO_0(
    v__cps__df__rowmono_0_andThenIO_4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl5_x[1]];
          }
          case 4: {
            return [5, v__inl5_x[1]];
          }
        }
      })(v__inl5_x),
      [10]
    ),
    [8]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
