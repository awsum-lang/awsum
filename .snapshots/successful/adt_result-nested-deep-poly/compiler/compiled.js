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

  const main = (() => {
    let v__inl28_scrut;
    $join27: {
      const __s = __concat(
        (v__inl3_r =>
          (s => {
            switch (s[0]) {
              case 24: {
                const v__inl1___p0_p0 = s[1];
                return v__inl1___p0_p0[1];
              }
              case 25: {
                const v__inl2___p0_p0 = s[1];
                return v__inl2___p0_p0[1];
              }
            }
          })(v__inl3_r[1]))([24, [24, [24, "1"]]]),
        ","
      );
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s0 = __s[1];
          v__inl28_scrut = (s => {
            switch (s[0]) {
              case 3: {
                const v__do_e_11 = s[1];
                return [3, v__do_e_11];
              }
              case 4: {
                const v_s1 = s[1];
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
                                  const v__inl7___p0_p0 = s[1];
                                  return v__inl7___p0_p0[1];
                                }
                                case 25: {
                                  const v__inl8___p0_p0 = s[1];
                                  return v__inl8___p0_p0[1];
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
                                              const v__inl10___p0_p0 = s[1];
                                              return v__inl10___p0_p0[1];
                                            }
                                            case 25: {
                                              const v__inl11___p0_p0 = s[1];
                                              return v__inl11___p0_p0[1];
                                            }
                                          }
                                        })(v__inl12_r[1]))(
                                        [24, [25, [25, "4"]]]
                                      )
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
                                                          const v__inl13___p0_p0 = s[1];
                                                          return v__inl13___p0_p0[1];
                                                        }
                                                        case 25: {
                                                          const v__inl14___p0_p0 = s[1];
                                                          return v__inl14___p0_p0[1];
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
                                                                      const v__inl16___p0_p0 = s[1];
                                                                      return v__inl16___p0_p0[1];
                                                                    }
                                                                    case 25: {
                                                                      const v__inl17___p0_p0 = s[1];
                                                                      return v__inl17___p0_p0[1];
                                                                    }
                                                                  }
                                                                })(
                                                                  v__inl18_r[1]
                                                                ))(
                                                                [
                                                                  25,
                                                                  [
                                                                    24,
                                                                    [25, "6"]
                                                                  ]
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
                                                                                  const v__inl19___p0_p0 = s[1];
                                                                                  return v__inl19___p0_p0[1];
                                                                                }
                                                                                case 25: {
                                                                                  const v__inl20___p0_p0 = s[1];
                                                                                  return v__inl20___p0_p0[1];
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
                                                                                            const v__inl22___p0_p0 = s[1];
                                                                                            return v__inl22___p0_p0[1];
                                                                                          }
                                                                                          case 25: {
                                                                                            const v__inl23___p0_p0 = s[1];
                                                                                            return v__inl23___p0_p0[1];
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
          })(
            __concat(
              v_s0,
              (v__inl6_r =>
                (s => {
                  switch (s[0]) {
                    case 24: {
                      const v__inl4___p0_p0 = s[1];
                      return v__inl4___p0_p0[1];
                    }
                    case 25: {
                      const v__inl5___p0_p0 = s[1];
                      return v__inl5___p0_p0[1];
                    }
                  }
                })(v__inl6_r[1]))([24, [24, [25, "2"]]])
            )
          );
          break $join27;
        }
      }
    }
    switch (v__inl28_scrut[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        return [7, v__inl28_scrut[1], [5, [0]]];
      }
    }
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
