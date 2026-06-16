"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __splitOnFirst = (sep, str) => {
    const i = str.indexOf(sep);
    if (i < 0) {
      return [11];
    }
    return [12, [15, str.substring(0, i), str.substring(i + sep.length)]];
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

  const v_render = v_r => {
    switch (v_r[0]) {
      case 11: {
        return [4, "Nothing"];
      }
      case 12: {
        const v_t = v_r[1];
        {
          const __s = __concat("Just(", v_t[1]);
          switch (__s[0]) {
            case 3: {
              const v__inl1__do_e_2 = __s[1];
              return [3, v__inl1__do_e_2];
            }
            case 4: {
              const v__inl2_s0 = __s[1];
              {
                const __s = __concat(v__inl2_s0, "|");
                switch (__s[0]) {
                  case 3: {
                    const v__inl3__do_e_1 = __s[1];
                    return [3, v__inl3__do_e_1];
                  }
                  case 4: {
                    const v__inl4_s1 = __s[1];
                    {
                      const __s = __concat(v__inl4_s1, v_t[2]);
                      switch (__s[0]) {
                        case 3: {
                          const v__inl5__do_e_0 = __s[1];
                          return [3, v__inl5__do_e_0];
                        }
                        case 4: {
                          const v__inl6_s2 = __s[1];
                          return __concat(v__inl6_s2, ")");
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
  };

  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_23 = s[1];
        return [3, v__do_e_23];
      }
      case 4: {
        const v_a = s[1];
        {
          const __s = v_render(__splitOnFirst("::", "user::42::admin"));
          switch (__s[0]) {
            case 3: {
              const v__do_e_22 = __s[1];
              return [3, v__do_e_22];
            }
            case 4: {
              const v_b = __s[1];
              {
                const __s = v_render(__splitOnFirst("x", "abc"));
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_21 = __s[1];
                    return [3, v__do_e_21];
                  }
                  case 4: {
                    const v_c = __s[1];
                    {
                      const __s = v_render(__splitOnFirst("", "abc"));
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_20 = __s[1];
                          return [3, v__do_e_20];
                        }
                        case 4: {
                          const v_d = __s[1];
                          {
                            const __s = v_render(__splitOnFirst(":", ":foo"));
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_19 = __s[1];
                                return [3, v__do_e_19];
                              }
                              case 4: {
                                const v_e = __s[1];
                                {
                                  const __s = v_render(
                                    __splitOnFirst(":", "foo:")
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_18 = __s[1];
                                      return [3, v__do_e_18];
                                    }
                                    case 4: {
                                      const v_f = __s[1];
                                      {
                                        const __s = v_render(
                                          __splitOnFirst("abc", "abc")
                                        );
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_17 = __s[1];
                                            return [3, v__do_e_17];
                                          }
                                          case 4: {
                                            const v_g = __s[1];
                                            {
                                              const __s = v_render(
                                                __splitOnFirst("abcde", "ab")
                                              );
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__do_e_16 = __s[1];
                                                  return [3, v__do_e_16];
                                                }
                                                case 4: {
                                                  const v_h = __s[1];
                                                  {
                                                    const __s = __concat(
                                                      v_a,
                                                      ", "
                                                    );
                                                    switch (__s[0]) {
                                                      case 3: {
                                                        const v__do_e_15 = __s[1];
                                                        return [3, v__do_e_15];
                                                      }
                                                      case 4: {
                                                        const v_r0 = __s[1];
                                                        {
                                                          const __s = __concat(
                                                            v_r0,
                                                            v_b
                                                          );
                                                          switch (__s[0]) {
                                                            case 3: {
                                                              const v__do_e_14 = __s[1];
                                                              return [
                                                                3,
                                                                v__do_e_14
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v_r1 = __s[1];
                                                              {
                                                                const __s = __concat(
                                                                  v_r1,
                                                                  ", "
                                                                );
                                                                switch (__s[0]) {
                                                                  case 3: {
                                                                    const v__do_e_13 = __s[1];
                                                                    return [
                                                                      3,
                                                                      v__do_e_13
                                                                    ];
                                                                  }
                                                                  case 4: {
                                                                    const v_r2 = __s[1];
                                                                    {
                                                                      const __s = __concat(
                                                                        v_r2,
                                                                        v_c
                                                                      );
                                                                      switch (__s[0]) {
                                                                        case 3: {
                                                                          const v__do_e_12 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v__do_e_12
                                                                          ];
                                                                        }
                                                                        case 4: {
                                                                          const v_r3 = __s[1];
                                                                          {
                                                                            const __s = __concat(
                                                                              v_r3,
                                                                              ", "
                                                                            );
                                                                            switch (__s[0]) {
                                                                              case 3: {
                                                                                const v__do_e_11 = __s[1];
                                                                                return [
                                                                                  3,
                                                                                  v__do_e_11
                                                                                ];
                                                                              }
                                                                              case 4: {
                                                                                const v_r4 = __s[1];
                                                                                {
                                                                                  const __s = __concat(
                                                                                    v_r4,
                                                                                    v_d
                                                                                  );
                                                                                  switch (__s[0]) {
                                                                                    case 3: {
                                                                                      const v__do_e_10 = __s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v__do_e_10
                                                                                      ];
                                                                                    }
                                                                                    case 4: {
                                                                                      const v_r5 = __s[1];
                                                                                      {
                                                                                        const __s = __concat(
                                                                                          v_r5,
                                                                                          ", "
                                                                                        );
                                                                                        switch (__s[0]) {
                                                                                          case 3: {
                                                                                            const v__do_e_9 = __s[1];
                                                                                            return [
                                                                                              3,
                                                                                              v__do_e_9
                                                                                            ];
                                                                                          }
                                                                                          case 4: {
                                                                                            const v_r6 = __s[1];
                                                                                            {
                                                                                              const __s = __concat(
                                                                                                v_r6,
                                                                                                v_e
                                                                                              );
                                                                                              switch (__s[0]) {
                                                                                                case 3: {
                                                                                                  const v__do_e_8 = __s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v__do_e_8
                                                                                                  ];
                                                                                                }
                                                                                                case 4: {
                                                                                                  const v_r7 = __s[1];
                                                                                                  {
                                                                                                    const __s = __concat(
                                                                                                      v_r7,
                                                                                                      ", "
                                                                                                    );
                                                                                                    switch (__s[0]) {
                                                                                                      case 3: {
                                                                                                        const v__do_e_7 = __s[1];
                                                                                                        return [
                                                                                                          3,
                                                                                                          v__do_e_7
                                                                                                        ];
                                                                                                      }
                                                                                                      case 4: {
                                                                                                        const v_r8 = __s[1];
                                                                                                        {
                                                                                                          const __s = __concat(
                                                                                                            v_r8,
                                                                                                            v_f
                                                                                                          );
                                                                                                          switch (__s[0]) {
                                                                                                            case 3: {
                                                                                                              const v__do_e_6 = __s[1];
                                                                                                              return [
                                                                                                                3,
                                                                                                                v__do_e_6
                                                                                                              ];
                                                                                                            }
                                                                                                            case 4: {
                                                                                                              const v_r9 = __s[1];
                                                                                                              {
                                                                                                                const __s = __concat(
                                                                                                                  v_r9,
                                                                                                                  ", "
                                                                                                                );
                                                                                                                switch (__s[0]) {
                                                                                                                  case 3: {
                                                                                                                    const v__do_e_5 = __s[1];
                                                                                                                    return [
                                                                                                                      3,
                                                                                                                      v__do_e_5
                                                                                                                    ];
                                                                                                                  }
                                                                                                                  case 4: {
                                                                                                                    const v_r10 = __s[1];
                                                                                                                    {
                                                                                                                      const __s = __concat(
                                                                                                                        v_r10,
                                                                                                                        v_g
                                                                                                                      );
                                                                                                                      switch (__s[0]) {
                                                                                                                        case 3: {
                                                                                                                          const v__do_e_4 = __s[1];
                                                                                                                          return [
                                                                                                                            3,
                                                                                                                            v__do_e_4
                                                                                                                          ];
                                                                                                                        }
                                                                                                                        case 4: {
                                                                                                                          const v_r11 = __s[1];
                                                                                                                          {
                                                                                                                            const __s = __concat(
                                                                                                                              v_r11,
                                                                                                                              ", "
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
                                                                                                                                const v_r12 = __s[1];
                                                                                                                                return __concat(
                                                                                                                                  v_r12,
                                                                                                                                  v_h
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
  })(v_render(__splitOnFirst(",", "a,b,c")));

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

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (v__inl9_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl9_x[1]];
            }
            case 4: {
              return [5, v__inl9_x[1]];
            }
          }
        })(v__inl9_x))(v_res),
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
