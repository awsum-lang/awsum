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

  const v_defaultRight = [4, [12, [2]]];

  const v_defaultJust = [12, [1]];

  const v_defaultBools = [26, [1], [26, [2], [25]]];

  const v__apply_describeLst = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_28;
              continue;
            }
            case 4: {
              v__x = __concat(
                (v__inl6_x =>
                  (s => {
                    switch (s[0]) {
                      case 1: {
                        return "T";
                      }
                      case 2: {
                        return "F";
                      }
                    }
                  })(v__inl6_x[1]))(v__k[2]),
                v__x[1]
              );
              v__k = v__pk_28;
              continue;
            }
          }
        }
      }
    }
  };

  const v__cps_describeLst = (v_xs, v__k) => {
    while (true) {
      switch (v_xs[0]) {
        case 25: {
          return v__apply_describeLst(v__k, [4, ""]);
        }
        case 26: {
          const v_h = v_xs[1];
          const v_t = v_xs[2];
          v__k = [28, v__k, v_h];
          v_xs = v_t;
          continue;
        }
      }
    }
  };

  const v__apply__lift_14 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 29: {
          return v__x;
        }
        case 30: {
          const v__pk_30 = v__k[1];
          const v___f0 = v__k[2];
          v__x = (v__k[0] = 26, v__k[1] = [
            796142685,
            v___f0
          ], v__k[2] = v__x, v__k);
          v__k = v__pk_30;
          continue;
        }
      }
    }
  };

  const v__cps__lift_14 = (v___input, v__k) => {
    while (true) {
      switch (v___input[0]) {
        case 25: {
          return v__apply__lift_14(v__k, v___input);
        }
        case 26: {
          const v___f0 = v___input[1];
          const v___f1 = v___input[2];
          v__k = [30, v__k, v___f0];
          v___input = v___f1;
          continue;
        }
      }
    }
  };

  const v_summary = (v__inl11_m =>
    (s => {
      switch (s[0]) {
        case 3: {
          const v__do_e_6 = s[1];
          return [3, v__do_e_6];
        }
        case 4: {
          const v_a = s[1];
          {
            const __s = v__cps_describeLst(
              v__cps__lift_14(v_defaultBools, [29]),
              [27]
            );
            switch (__s[0]) {
              case 3: {
                const v__do_e_5 = __s[1];
                return [3, v__do_e_5];
              }
              case 4: {
                const v_b = __s[1];
                const v__inl21_r = (v__inl15___input =>
                  (s => {
                    switch (s[0]) {
                      case 3: {
                        return v__inl15___input;
                      }
                      case 4: {
                        const v__inl13___f0 = s[1];
                        return [
                          4,
                          (s => {
                            switch (s[0]) {
                              case 11: {
                                return v__inl13___f0;
                              }
                              case 12: {
                                return [12, [796142685, v__inl13___f0[1]]];
                              }
                            }
                          })(v__inl13___f0)
                        ];
                      }
                    }
                  })(v__inl15___input))(v_defaultRight);
                {
                  const __s = (s => {
                    switch (s[0]) {
                      case 3: {
                        return [4, "ErrA"];
                      }
                      case 4: {
                        const v__inl18_m = v__inl21_r[1];
                        switch (v__inl18_m[0]) {
                          case 11: {
                            return [4, "N"];
                          }
                          case 12: {
                            return __concat(
                              "J",
                              (v__inl20_x =>
                                (s => {
                                  switch (s[0]) {
                                    case 1: {
                                      return "T";
                                    }
                                    case 2: {
                                      return "F";
                                    }
                                  }
                                })(v__inl20_x[1]))(v__inl18_m[1])
                            );
                          }
                        }
                      }
                    }
                  })(v__inl21_r);
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_4 = __s[1];
                      return [3, v__do_e_4];
                    }
                    case 4: {
                      const v_c = __s[1];
                      {
                        const __s = __concat(v_a, " / ");
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_3 = __s[1];
                            return [3, v__do_e_3];
                          }
                          case 4: {
                            const v_s0 = __s[1];
                            {
                              const __s = __concat(v_s0, v_b);
                              switch (__s[0]) {
                                case 3: {
                                  const v__do_e_2 = __s[1];
                                  return [3, v__do_e_2];
                                }
                                case 4: {
                                  const v_s1 = __s[1];
                                  {
                                    const __s = __concat(v_s1, " / ");
                                    switch (__s[0]) {
                                      case 3: {
                                        const v__do_e_1 = __s[1];
                                        return [3, v__do_e_1];
                                      }
                                      case 4: {
                                        const v_s2 = __s[1];
                                        return __concat(v_s2, v_c);
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
          case 11: {
            return [4, "N"];
          }
          case 12: {
            return __concat(
              "J",
              (v__inl10_x =>
                (s => {
                  switch (s[0]) {
                    case 1: {
                      return "T";
                    }
                    case 2: {
                      return "F";
                    }
                  }
                })(v__inl10_x[1]))(v__inl11_m[1])
            );
          }
        }
      })(v__inl11_m)
    ))(
    (v__inl8___input =>
      (s => {
        switch (s[0]) {
          case 11: {
            return v__inl8___input;
          }
          case 12: {
            return [12, [796142685, v__inl8___input[1]]];
          }
        }
      })(v__inl8___input))(v_defaultJust)
  );

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        const v__inl23_s = s[1];
        return [7, v__inl23_s, [5, [0]]];
      }
    }
  })(v_summary);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
