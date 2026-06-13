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

  const v_minInt32 = -2147483648 | 0;

  const v_maxInt32 = 2147483647 | 0;

  const main = (() => {
    let v__inl4_scrut;
    $join3: {
      const __s = __concat(String(v_minInt32), ", ");
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s0 = __s[1];
          v__inl4_scrut = (s => {
            switch (s[0]) {
              case 3: {
                const v__do_e_7 = s[1];
                return [3, v__do_e_7];
              }
              case 4: {
                const v_s1 = s[1];
                {
                  const __s = __concat(v_s1, ", ");
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_6 = __s[1];
                      return [3, v__do_e_6];
                    }
                    case 4: {
                      const v_s2 = __s[1];
                      {
                        const __s = __concat(v_s2, String(0 | 0));
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_5 = __s[1];
                            return [3, v__do_e_5];
                          }
                          case 4: {
                            const v_s3 = __s[1];
                            {
                              const __s = __concat(v_s3, ", ");
                              switch (__s[0]) {
                                case 3: {
                                  const v__do_e_4 = __s[1];
                                  return [3, v__do_e_4];
                                }
                                case 4: {
                                  const v_s4 = __s[1];
                                  {
                                    const __s = __concat(v_s4, String(7 | 0));
                                    switch (__s[0]) {
                                      case 3: {
                                        const v__do_e_3 = __s[1];
                                        return [3, v__do_e_3];
                                      }
                                      case 4: {
                                        const v_s5 = __s[1];
                                        {
                                          const __s = __concat(v_s5, ", ");
                                          switch (__s[0]) {
                                            case 3: {
                                              const v__do_e_2 = __s[1];
                                              return [3, v__do_e_2];
                                            }
                                            case 4: {
                                              const v_s6 = __s[1];
                                              {
                                                const __s = __concat(
                                                  v_s6,
                                                  String(1234567 | 0)
                                                );
                                                switch (__s[0]) {
                                                  case 3: {
                                                    const v__do_e_1 = __s[1];
                                                    return [3, v__do_e_1];
                                                  }
                                                  case 4: {
                                                    const v_s7 = __s[1];
                                                    {
                                                      const __s = __concat(
                                                        v_s7,
                                                        ", "
                                                      );
                                                      switch (__s[0]) {
                                                        case 3: {
                                                          const v__do_e_0 = __s[1];
                                                          return [3, v__do_e_0];
                                                        }
                                                        case 4: {
                                                          const v_s8 = __s[1];
                                                          return __concat(
                                                            v_s8,
                                                            String(v_maxInt32)
                                                          );
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
            }
          })(__concat(v_s0, String(-42 | 0)));
          break $join3;
        }
      }
    }
    switch (v__inl4_scrut[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        return [7, v__inl4_scrut[1], [5, [0]]];
      }
    }
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
