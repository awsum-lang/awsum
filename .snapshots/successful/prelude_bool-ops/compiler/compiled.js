"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_3 = s[1];
        return [3, v__do_e_3];
      }
      case 4: {
        const v_s0 = s[1];
        {
          const v__inl1_a = [1];
          const __s = __concat(
            v_s0,
            (() => {
              let v__inl6_scrut;
              $join5: {
                switch (v__inl1_a[0]) {
                  case 1: {
                    return "False";
                  }
                  case 2: {
                    v__inl6_scrut = v__inl1_a;
                    break $join5;
                  }
                }
              }
              switch (v__inl6_scrut[0]) {
                case 1: {
                  return "True";
                }
                case 2: {
                  return "False";
                }
              }
            })()
          );
          switch (__s[0]) {
            case 3: {
              const v__do_e_2 = __s[1];
              return [3, v__do_e_2];
            }
            case 4: {
              const v_s1 = __s[1];
              {
                const __s = __concat(v_s1, "True");
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_1 = __s[1];
                    return [3, v__do_e_1];
                  }
                  case 4: {
                    const v_s2 = __s[1];
                    {
                      const __s = __concat(v_s2, "False");
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_0 = __s[1];
                          return [3, v__do_e_0];
                        }
                        case 4: {
                          const v_s3 = __s[1];
                          return __concat(v_s3, "True");
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
    }
  })(__concat("False", "True"));

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
          const v__pk_21 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_21;
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
          v__k = [21, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
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
          v__k = [23, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl9_x = v_res;
  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl9_x[1]];
          }
          case 4: {
            return [5, v__inl9_x[1]];
          }
        }
      })(v__inl9_x),
      [22]
    ),
    [20]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
