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

  const v__scc_evenInt_oddInt = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 20: {
          const v_n = v__args[1];
          {
            const __s = __eqInt32(v_n, 0 | 0);
            switch (__s[0]) {
              case 1: {
                return [4, [1]];
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
                      v__args = (v__args[0] = 21, v__args[1] = v_m, v__args);
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 21: {
          const v_n = v__args[1];
          {
            const __s = __eqInt32(v_n, 0 | 0);
            switch (__s[0]) {
              case 1: {
                return [4, [2]];
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
                      v__args = (v__args[0] = 20, v__args[1] = v_m, v__args);
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

  const v_res = (v__inl3_r =>
    (s => {
      switch (s[0]) {
        case 3: {
          return __concat("left: ", "UnderflowError");
        }
        case 4: {
          return __concat(
            "right: ",
            (s => {
              switch (s[0]) {
                case 1: {
                  return "True";
                }
                case 2: {
                  return "False";
                }
              }
            })(v__inl3_r[1])
          );
        }
      }
    })(v__inl3_r))(v__scc_evenInt_oddInt([20, 1000000 | 0]));

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 22: {
          return v__x;
        }
        case 23: {
          const v__pk_23 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_23;
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
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [23, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 24: {
          return v__x;
        }
        case 25: {
          const v__pk_25 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_25;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_4(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [25, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (v__inl6_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl6_x[1]];
            }
            case 4: {
              return [5, v__inl6_x[1]];
            }
          }
        })(v__inl6_x))(v_res),
      [24]
    ),
    [22]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
