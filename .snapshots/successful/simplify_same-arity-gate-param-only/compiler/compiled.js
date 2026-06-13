"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const v_spin = (v_c, v_q2) => {
    while (true) {
      {
        const __s = __eqInt32(v_c, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_q2;
          }
          case 2: {
            {
              const __s = __predInt32(v_c);
              switch (__s[0]) {
                case 3: {
                  return v_q2;
                }
                case 4: {
                  const v_m2 = __s[1];
                  switch (v_q2[0]) {
                    case 24: {
                      const v_x3 = v_q2[1];
                      const v_y3 = v_q2[2];
                      v_c = v_m2;
                      v_q2 = [24, v_y3, v_x3];
                      continue;
                    }
                    case 25: {
                      v_c = v_m2;
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

  const v_make = v_n => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [26, [24, "a", "b"]];
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  return [26, [25, "u"]];
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

  const v_eat = (v_k, v_q) => {
    while (true) {
      {
        const __s = __eqInt32(v_k, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_q[1];
          }
          case 2: {
            {
              const __s = __predInt32(v_k);
              switch (__s[0]) {
                case 3: {
                  return "u";
                }
                case 4: {
                  const v_j = __s[1];
                  v_k = v_j;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_28;
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
              v_eat(
                0 | 0,
                v_spin(
                  1 | 0,
                  (s => {
                    switch (s[0]) {
                      case 26: {
                        const v__inl5_p = s[1];
                        switch (v__inl5_p[0]) {
                          case 24: {
                            return [24, v__inl5_p[2], v__inl5_p[1]];
                          }
                          case 25: {
                            return v__inl5_p;
                          }
                        }
                      }
                    }
                  })(v_make(0 | 0))
                )
              ),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [28, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_andThenIO_0(
    [
      7,
      v_eat(
        1 | 0,
        (s => {
          switch (s[0]) {
            case 26: {
              const v__inl9_p = s[1];
              switch (v__inl9_p[0]) {
                case 24: {
                  return [24, v__inl9_p[2], v__inl9_p[1]];
                }
                case 25: {
                  return v__inl9_p;
                }
              }
            }
          }
        })(v_make(1 | 0))
      ),
      [5, [0]]
    ],
    [27]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
