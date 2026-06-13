"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __negInt32 = x => x === -2147483648 ? [3, [18]] : [4, -x | 0];

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

  const main = (v__inl3_r =>
    (() => {
      let v__inl19_scrut;
      $join18: {
        const __s = (s => {
          switch (s[0]) {
            case 3: {
              return __concat("overflow: ", "OverflowError");
            }
            case 4: {
              return __concat("ok: ", String(v__inl3_r[1]));
            }
          }
        })(v__inl3_r);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl19_scrut = (v__inl6_r =>
              (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_10 = s[1];
                    return [3, v__do_e_10];
                  }
                  case 4: {
                    const v_b = s[1];
                    const v__inl9_r = [4, 0 | 0];
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 3: {
                            return __concat("overflow: ", "OverflowError");
                          }
                          case 4: {
                            return __concat("ok: ", String(v__inl9_r[1]));
                          }
                        }
                      })(v__inl9_r);
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_9 = __s[1];
                          return [3, v__do_e_9];
                        }
                        case 4: {
                          const v_c = __s[1];
                          const v__inl12_r = __negInt32(v_maxInt32);
                          {
                            const __s = (s => {
                              switch (s[0]) {
                                case 3: {
                                  return __concat(
                                    "overflow: ",
                                    "OverflowError"
                                  );
                                }
                                case 4: {
                                  return __concat(
                                    "ok: ",
                                    String(v__inl12_r[1])
                                  );
                                }
                              }
                            })(v__inl12_r);
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_8 = __s[1];
                                return [3, v__do_e_8];
                              }
                              case 4: {
                                const v_d = __s[1];
                                const v__inl15_r = __negInt32(v_minInt32);
                                {
                                  const __s = (s => {
                                    switch (s[0]) {
                                      case 3: {
                                        return __concat(
                                          "overflow: ",
                                          "OverflowError"
                                        );
                                      }
                                      case 4: {
                                        return __concat(
                                          "ok: ",
                                          String(v__inl15_r[1])
                                        );
                                      }
                                    }
                                  })(v__inl15_r);
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_7 = __s[1];
                                      return [3, v__do_e_7];
                                    }
                                    case 4: {
                                      const v_e = __s[1];
                                      {
                                        const __s = __concat(v_a, ", ");
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_6 = __s[1];
                                            return [3, v__do_e_6];
                                          }
                                          case 4: {
                                            const v_s0 = __s[1];
                                            {
                                              const __s = __concat(v_s0, v_b);
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__do_e_5 = __s[1];
                                                  return [3, v__do_e_5];
                                                }
                                                case 4: {
                                                  const v_s1 = __s[1];
                                                  {
                                                    const __s = __concat(
                                                      v_s1,
                                                      ", "
                                                    );
                                                    switch (__s[0]) {
                                                      case 3: {
                                                        const v__do_e_4 = __s[1];
                                                        return [3, v__do_e_4];
                                                      }
                                                      case 4: {
                                                        const v_s2 = __s[1];
                                                        {
                                                          const __s = __concat(
                                                            v_s2,
                                                            v_c
                                                          );
                                                          switch (__s[0]) {
                                                            case 3: {
                                                              const v__do_e_3 = __s[1];
                                                              return [
                                                                3,
                                                                v__do_e_3
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v_s3 = __s[1];
                                                              {
                                                                const __s = __concat(
                                                                  v_s3,
                                                                  ", "
                                                                );
                                                                switch (__s[0]) {
                                                                  case 3: {
                                                                    const v__do_e_2 = __s[1];
                                                                    return [
                                                                      3,
                                                                      v__do_e_2
                                                                    ];
                                                                  }
                                                                  case 4: {
                                                                    const v_s4 = __s[1];
                                                                    {
                                                                      const __s = __concat(
                                                                        v_s4,
                                                                        v_d
                                                                      );
                                                                      switch (__s[0]) {
                                                                        case 3: {
                                                                          const v__do_e_1 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v__do_e_1
                                                                          ];
                                                                        }
                                                                        case 4: {
                                                                          const v_s5 = __s[1];
                                                                          {
                                                                            const __s = __concat(
                                                                              v_s5,
                                                                              ", "
                                                                            );
                                                                            switch (__s[0]) {
                                                                              case 3: {
                                                                                const v__do_e_0 = __s[1];
                                                                                return [
                                                                                  3,
                                                                                  v__do_e_0
                                                                                ];
                                                                              }
                                                                              case 4: {
                                                                                const v_s6 = __s[1];
                                                                                return __concat(
                                                                                  v_s6,
                                                                                  v_e
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
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })(
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return __concat("overflow: ", "OverflowError");
                    }
                    case 4: {
                      return __concat("ok: ", String(v__inl6_r[1]));
                    }
                  }
                })(v__inl6_r)
              ))([4, 5 | 0]);
            break $join18;
          }
        }
      }
      switch (v__inl19_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl19_scrut[1], [5, [0]]];
        }
      }
    })())([4, -5 | 0]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
