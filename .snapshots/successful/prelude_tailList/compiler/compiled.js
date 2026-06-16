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

  const v__apply_showList = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
          const v__pk_21 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_21;
              continue;
            }
            case 4: {
              const v_rest = v__x[1];
              {
                const __s = __concat(v__k[2], ",");
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_0 = __s[1];
                    v__k = v__pk_21;
                    v__x = [3, v__do_e_0];
                    continue;
                  }
                  case 4: {
                    const v_hc = __s[1];
                    v__k = v__pk_21;
                    v__x = __concat(v_hc, v_rest);
                    continue;
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  const v__cps_showList = (v_xs, v__k) => {
    while (true) {
      switch (v_xs[0]) {
        case 13: {
          return v__apply_showList(v__k, [4, "Nil"]);
        }
        case 14: {
          const v_h = v_xs[1];
          const v_t = v_xs[2];
          v__k = [21, v__k, v_h];
          v_xs = v_t;
          continue;
        }
      }
    }
  };

  const v_res = (v__inl66_xs =>
    (s => {
      switch (s[0]) {
        case 3: {
          const v__inl70__do_e_8 = s[1];
          return [3, v__inl70__do_e_8];
        }
        case 4: {
          const v__inl71_a = s[1];
          const v__inl72_xs = [14, "a", [13]];
          {
            const __s = (s => {
              switch (s[0]) {
                case 13: {
                  return [4, "Nothing"];
                }
                case 14: {
                  {
                    const __s = v__cps_showList(v__inl72_xs[2], [20]);
                    switch (__s[0]) {
                      case 3: {
                        const v__inl75__do_e_2 = __s[1];
                        return [3, v__inl75__do_e_2];
                      }
                      case 4: {
                        const v__inl76_rendered = __s[1];
                        return __concat("Just ", v__inl76_rendered);
                      }
                    }
                  }
                }
              }
            })(v__inl72_xs);
            switch (__s[0]) {
              case 3: {
                const v__inl77__do_e_7 = __s[1];
                return [3, v__inl77__do_e_7];
              }
              case 4: {
                const v__inl78_b = __s[1];
                const v__inl79_xs = [14, "a", [14, "b", [14, "c", [13]]]];
                {
                  const __s = (s => {
                    switch (s[0]) {
                      case 13: {
                        return [4, "Nothing"];
                      }
                      case 14: {
                        {
                          const __s = v__cps_showList(v__inl79_xs[2], [20]);
                          switch (__s[0]) {
                            case 3: {
                              const v__inl82__do_e_2 = __s[1];
                              return [3, v__inl82__do_e_2];
                            }
                            case 4: {
                              const v__inl83_rendered = __s[1];
                              return __concat("Just ", v__inl83_rendered);
                            }
                          }
                        }
                      }
                    }
                  })(v__inl79_xs);
                  switch (__s[0]) {
                    case 3: {
                      const v__inl84__do_e_6 = __s[1];
                      return [3, v__inl84__do_e_6];
                    }
                    case 4: {
                      const v__inl85_c = __s[1];
                      {
                        const __s = __concat(v__inl71_a, "|");
                        switch (__s[0]) {
                          case 3: {
                            const v__inl86__do_e_5 = __s[1];
                            return [3, v__inl86__do_e_5];
                          }
                          case 4: {
                            const v__inl87_s0 = __s[1];
                            {
                              const __s = __concat(v__inl87_s0, v__inl78_b);
                              switch (__s[0]) {
                                case 3: {
                                  const v__inl88__do_e_4 = __s[1];
                                  return [3, v__inl88__do_e_4];
                                }
                                case 4: {
                                  const v__inl89_s1 = __s[1];
                                  {
                                    const __s = __concat(v__inl89_s1, "|");
                                    switch (__s[0]) {
                                      case 3: {
                                        const v__inl90__do_e_3 = __s[1];
                                        return [3, v__inl90__do_e_3];
                                      }
                                      case 4: {
                                        const v__inl91_s2 = __s[1];
                                        return __concat(
                                          v__inl91_s2,
                                          v__inl85_c
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
    })(
      (s => {
        switch (s[0]) {
          case 13: {
            return [4, "Nothing"];
          }
          case 14: {
            {
              const __s = v__cps_showList(v__inl66_xs[2], [20]);
              switch (__s[0]) {
                case 3: {
                  const v__inl92__do_e_2 = __s[1];
                  return [3, v__inl92__do_e_2];
                }
                case 4: {
                  const v__inl93_rendered = __s[1];
                  return __concat("Just ", v__inl93_rendered);
                }
              }
            }
          }
        }
      })(v__inl66_xs)
    ))([13]);

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
      (v__inl96_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl96_x[1]];
            }
            case 4: {
              return [5, v__inl96_x[1]];
            }
          }
        })(v__inl96_x))(v_res),
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
