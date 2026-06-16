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
        const v__do_e_12 = s[1];
        return [3, v__do_e_12];
      }
      case 4: {
        const v_s0 = s[1];
        {
          const __s = __concat(
            v_s0,
            (v__inl6_r =>
              (s => {
                switch (s[0]) {
                  case 24: {
                    const v__inl4_inner2 = s[1];
                    return v__inl4_inner2[1];
                  }
                  case 25: {
                    const v__inl5_inner2 = s[1];
                    return v__inl5_inner2[1];
                  }
                }
              })(v__inl6_r[1]))([24, [24, [25, "2"]]])
          );
          switch (__s[0]) {
            case 3: {
              const v__do_e_11 = __s[1];
              return [3, v__do_e_11];
            }
            case 4: {
              const v_s1 = __s[1];
              {
                const __s = __concat(v_s1, ",");
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_10 = __s[1];
                    return [3, v__do_e_10];
                  }
                  case 4: {
                    const v_s2 = __s[1];
                    {
                      const __s = __concat(
                        v_s2,
                        (v__inl9_r =>
                          (s => {
                            switch (s[0]) {
                              case 24: {
                                const v__inl7_inner2 = s[1];
                                return v__inl7_inner2[1];
                              }
                              case 25: {
                                const v__inl8_inner2 = s[1];
                                return v__inl8_inner2[1];
                              }
                            }
                          })(v__inl9_r[1]))([24, [25, [24, "3"]]])
                      );
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_9 = __s[1];
                          return [3, v__do_e_9];
                        }
                        case 4: {
                          const v_s3 = __s[1];
                          {
                            const __s = __concat(v_s3, ",");
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_8 = __s[1];
                                return [3, v__do_e_8];
                              }
                              case 4: {
                                const v_s4 = __s[1];
                                {
                                  const __s = __concat(
                                    v_s4,
                                    (v__inl12_r =>
                                      (s => {
                                        switch (s[0]) {
                                          case 24: {
                                            const v__inl10_inner2 = s[1];
                                            return v__inl10_inner2[1];
                                          }
                                          case 25: {
                                            const v__inl11_inner2 = s[1];
                                            return v__inl11_inner2[1];
                                          }
                                        }
                                      })(v__inl12_r[1]))([24, [25, [25, "4"]]])
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_7 = __s[1];
                                      return [3, v__do_e_7];
                                    }
                                    case 4: {
                                      const v_s5 = __s[1];
                                      {
                                        const __s = __concat(v_s5, ",");
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_6 = __s[1];
                                            return [3, v__do_e_6];
                                          }
                                          case 4: {
                                            const v_s6 = __s[1];
                                            {
                                              const __s = __concat(
                                                v_s6,
                                                (v__inl15_r =>
                                                  (s => {
                                                    switch (s[0]) {
                                                      case 24: {
                                                        const v__inl13_inner2 = s[1];
                                                        return v__inl13_inner2[1];
                                                      }
                                                      case 25: {
                                                        const v__inl14_inner2 = s[1];
                                                        return v__inl14_inner2[1];
                                                      }
                                                    }
                                                  })(v__inl15_r[1]))(
                                                  [25, [24, [24, "5"]]]
                                                )
                                              );
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__do_e_5 = __s[1];
                                                  return [3, v__do_e_5];
                                                }
                                                case 4: {
                                                  const v_s7 = __s[1];
                                                  {
                                                    const __s = __concat(
                                                      v_s7,
                                                      ","
                                                    );
                                                    switch (__s[0]) {
                                                      case 3: {
                                                        const v__do_e_4 = __s[1];
                                                        return [3, v__do_e_4];
                                                      }
                                                      case 4: {
                                                        const v_s8 = __s[1];
                                                        {
                                                          const __s = __concat(
                                                            v_s8,
                                                            (v__inl18_r =>
                                                              (s => {
                                                                switch (s[0]) {
                                                                  case 24: {
                                                                    const v__inl16_inner2 = s[1];
                                                                    return v__inl16_inner2[1];
                                                                  }
                                                                  case 25: {
                                                                    const v__inl17_inner2 = s[1];
                                                                    return v__inl17_inner2[1];
                                                                  }
                                                                }
                                                              })(
                                                                v__inl18_r[1]
                                                              ))(
                                                              [
                                                                25,
                                                                [24, [25, "6"]]
                                                              ]
                                                            )
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
                                                              const v_s9 = __s[1];
                                                              {
                                                                const __s = __concat(
                                                                  v_s9,
                                                                  ","
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
                                                                    const v_s10 = __s[1];
                                                                    {
                                                                      const __s = __concat(
                                                                        v_s10,
                                                                        (v__inl21_r =>
                                                                          (s => {
                                                                            switch (s[0]) {
                                                                              case 24: {
                                                                                const v__inl19_inner2 = s[1];
                                                                                return v__inl19_inner2[1];
                                                                              }
                                                                              case 25: {
                                                                                const v__inl20_inner2 = s[1];
                                                                                return v__inl20_inner2[1];
                                                                              }
                                                                            }
                                                                          })(
                                                                            v__inl21_r[1]
                                                                          ))(
                                                                          [
                                                                            25,
                                                                            [
                                                                              25,
                                                                              [
                                                                                24,
                                                                                "7"
                                                                              ]
                                                                            ]
                                                                          ]
                                                                        )
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
                                                                          const v_s11 = __s[1];
                                                                          {
                                                                            const __s = __concat(
                                                                              v_s11,
                                                                              ","
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
                                                                                const v_s12 = __s[1];
                                                                                return __concat(
                                                                                  v_s12,
                                                                                  (v__inl24_r =>
                                                                                    (s => {
                                                                                      switch (s[0]) {
                                                                                        case 24: {
                                                                                          const v__inl22_inner2 = s[1];
                                                                                          return v__inl22_inner2[1];
                                                                                        }
                                                                                        case 25: {
                                                                                          const v__inl23_inner2 = s[1];
                                                                                          return v__inl23_inner2[1];
                                                                                        }
                                                                                      }
                                                                                    })(
                                                                                      v__inl24_r[1]
                                                                                    ))(
                                                                                    [
                                                                                      25,
                                                                                      [
                                                                                        25,
                                                                                        [
                                                                                          25,
                                                                                          "8"
                                                                                        ]
                                                                                      ]
                                                                                    ]
                                                                                  )
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
  })(
    __concat(
      (v__inl3_r =>
        (s => {
          switch (s[0]) {
            case 24: {
              const v__inl1_inner2 = s[1];
              return v__inl1_inner2[1];
            }
            case 25: {
              const v__inl2_inner2 = s[1];
              return v__inl2_inner2[1];
            }
          }
        })(v__inl3_r[1]))([24, [24, [24, "1"]]]),
      ","
    )
  );

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
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
          v__k = [27, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          const v__pk_29 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_29;
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
          v__k = [29, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (v__inl27_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl27_x[1]];
            }
            case 4: {
              return [5, v__inl27_x[1]];
            }
          }
        })(v__inl27_x))(v_res),
      [28]
    ),
    [26]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
