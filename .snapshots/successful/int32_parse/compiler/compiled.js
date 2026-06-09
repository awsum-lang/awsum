"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const __parseInt32 = (s) => {
    if (!/^-?[0-9]+$/.test(s)) {
      return [3, [22]];
    }
    const n = Number(s);
    if (n < -2147483648 || n > 2147483647) {
      return [3, [22]];
    }
    return [4, n | 0];
  };

  const v_runIO = (v_io) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            {
              const __s = __print(v_s);
              switch (__s[0]) {
                case 0: {
                  const __t0 = v_next;
                  v_io = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_render = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [4, "err"];
        }
        case 4: {
          const v_v = __s[1];
          return __concat("ok:", String(v_v));
        }
      }
    }
  };

  const v__let_13 = (v_res) => {
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
  };

  const main = v__let_13(
    ((s) => {
      switch (s[0]) {
        case 3: {
          const v__do_e_32 = s[1];
          return [3, v__do_e_32];
        }
        case 4: {
          const v_a = s[1];
          return ((s) => {
            switch (s[0]) {
              case 3: {
                const v__do_e_31 = s[1];
                return [3, v__do_e_31];
              }
              case 4: {
                const v_b = s[1];
                return ((s) => {
                  switch (s[0]) {
                    case 3: {
                      const v__do_e_30 = s[1];
                      return [3, v__do_e_30];
                    }
                    case 4: {
                      const v_c = s[1];
                      return ((s) => {
                        switch (s[0]) {
                          case 3: {
                            const v__do_e_29 = s[1];
                            return [3, v__do_e_29];
                          }
                          case 4: {
                            const v_d = s[1];
                            return ((s) => {
                              switch (s[0]) {
                                case 3: {
                                  const v__do_e_28 = s[1];
                                  return [3, v__do_e_28];
                                }
                                case 4: {
                                  const v_e = s[1];
                                  return ((s) => {
                                    switch (s[0]) {
                                      case 3: {
                                        const v__do_e_27 = s[1];
                                        return [3, v__do_e_27];
                                      }
                                      case 4: {
                                        const v_f = s[1];
                                        return ((s) => {
                                          switch (s[0]) {
                                            case 3: {
                                              const v__do_e_26 = s[1];
                                              return [3, v__do_e_26];
                                            }
                                            case 4: {
                                              const v_g = s[1];
                                              return ((s) => {
                                                switch (s[0]) {
                                                  case 3: {
                                                    const v__do_e_25 = s[1];
                                                    return [3, v__do_e_25];
                                                  }
                                                  case 4: {
                                                    const v_h = s[1];
                                                    return ((s) => {
                                                      switch (s[0]) {
                                                        case 3: {
                                                          const v__do_e_24 = s[1];
                                                          return [
                                                            3,
                                                            v__do_e_24
                                                          ];
                                                        }
                                                        case 4: {
                                                          const v_i = s[1];
                                                          return ((s) => {
                                                            switch (s[0]) {
                                                              case 3: {
                                                                const v__do_e_23 = s[1];
                                                                return [
                                                                  3,
                                                                  v__do_e_23
                                                                ];
                                                              }
                                                              case 4: {
                                                                const v_j = s[1];
                                                                return ((s) => {
                                                                  switch (s[0]) {
                                                                    case 3: {
                                                                      const v__do_e_22 = s[1];
                                                                      return [
                                                                        3,
                                                                        v__do_e_22
                                                                      ];
                                                                    }
                                                                    case 4: {
                                                                      const v_k = s[1];
                                                                      return ((
                                                                        s
                                                                      ) => {
                                                                        switch (s[0]) {
                                                                          case 3: {
                                                                            const v__do_e_21 = s[1];
                                                                            return [
                                                                              3,
                                                                              v__do_e_21
                                                                            ];
                                                                          }
                                                                          case 4: {
                                                                            const v_l = s[1];
                                                                            return ((
                                                                              s
                                                                            ) => {
                                                                              switch (s[0]) {
                                                                                case 3: {
                                                                                  const v__do_e_20 = s[1];
                                                                                  return [
                                                                                    3,
                                                                                    v__do_e_20
                                                                                  ];
                                                                                }
                                                                                case 4: {
                                                                                  const v_s0 = s[1];
                                                                                  return ((
                                                                                    s
                                                                                  ) => {
                                                                                    switch (s[0]) {
                                                                                      case 3: {
                                                                                        const v__do_e_19 = s[1];
                                                                                        return [
                                                                                          3,
                                                                                          v__do_e_19
                                                                                        ];
                                                                                      }
                                                                                      case 4: {
                                                                                        const v_s1 = s[1];
                                                                                        return ((
                                                                                          s
                                                                                        ) => {
                                                                                          switch (s[0]) {
                                                                                            case 3: {
                                                                                              const v__do_e_18 = s[1];
                                                                                              return [
                                                                                                3,
                                                                                                v__do_e_18
                                                                                              ];
                                                                                            }
                                                                                            case 4: {
                                                                                              const v_s2 = s[1];
                                                                                              return ((
                                                                                                s
                                                                                              ) => {
                                                                                                switch (s[0]) {
                                                                                                  case 3: {
                                                                                                    const v__do_e_17 = s[1];
                                                                                                    return [
                                                                                                      3,
                                                                                                      v__do_e_17
                                                                                                    ];
                                                                                                  }
                                                                                                  case 4: {
                                                                                                    const v_s3 = s[1];
                                                                                                    return ((
                                                                                                      s
                                                                                                    ) => {
                                                                                                      switch (s[0]) {
                                                                                                        case 3: {
                                                                                                          const v__do_e_16 = s[1];
                                                                                                          return [
                                                                                                            3,
                                                                                                            v__do_e_16
                                                                                                          ];
                                                                                                        }
                                                                                                        case 4: {
                                                                                                          const v_s4 = s[1];
                                                                                                          return ((
                                                                                                            s
                                                                                                          ) => {
                                                                                                            switch (s[0]) {
                                                                                                              case 3: {
                                                                                                                const v__do_e_15 = s[1];
                                                                                                                return [
                                                                                                                  3,
                                                                                                                  v__do_e_15
                                                                                                                ];
                                                                                                              }
                                                                                                              case 4: {
                                                                                                                const v_s5 = s[1];
                                                                                                                return ((
                                                                                                                  s
                                                                                                                ) => {
                                                                                                                  switch (s[0]) {
                                                                                                                    case 3: {
                                                                                                                      const v__do_e_14 = s[1];
                                                                                                                      return [
                                                                                                                        3,
                                                                                                                        v__do_e_14
                                                                                                                      ];
                                                                                                                    }
                                                                                                                    case 4: {
                                                                                                                      const v_s6 = s[1];
                                                                                                                      return ((
                                                                                                                        s
                                                                                                                      ) => {
                                                                                                                        switch (s[0]) {
                                                                                                                          case 3: {
                                                                                                                            const v__do_e_13 = s[1];
                                                                                                                            return [
                                                                                                                              3,
                                                                                                                              v__do_e_13
                                                                                                                            ];
                                                                                                                          }
                                                                                                                          case 4: {
                                                                                                                            const v_s7 = s[1];
                                                                                                                            return ((
                                                                                                                              s
                                                                                                                            ) => {
                                                                                                                              switch (s[0]) {
                                                                                                                                case 3: {
                                                                                                                                  const v__do_e_12 = s[1];
                                                                                                                                  return [
                                                                                                                                    3,
                                                                                                                                    v__do_e_12
                                                                                                                                  ];
                                                                                                                                }
                                                                                                                                case 4: {
                                                                                                                                  const v_s8 = s[1];
                                                                                                                                  return ((
                                                                                                                                    s
                                                                                                                                  ) => {
                                                                                                                                    switch (s[0]) {
                                                                                                                                      case 3: {
                                                                                                                                        const v__do_e_11 = s[1];
                                                                                                                                        return [
                                                                                                                                          3,
                                                                                                                                          v__do_e_11
                                                                                                                                        ];
                                                                                                                                      }
                                                                                                                                      case 4: {
                                                                                                                                        const v_s9 = s[1];
                                                                                                                                        return ((
                                                                                                                                          s
                                                                                                                                        ) => {
                                                                                                                                          switch (s[0]) {
                                                                                                                                            case 3: {
                                                                                                                                              const v__do_e_10 = s[1];
                                                                                                                                              return [
                                                                                                                                                3,
                                                                                                                                                v__do_e_10
                                                                                                                                              ];
                                                                                                                                            }
                                                                                                                                            case 4: {
                                                                                                                                              const v_s10 = s[1];
                                                                                                                                              return ((
                                                                                                                                                s
                                                                                                                                              ) => {
                                                                                                                                                switch (s[0]) {
                                                                                                                                                  case 3: {
                                                                                                                                                    const v__do_e_9 = s[1];
                                                                                                                                                    return [
                                                                                                                                                      3,
                                                                                                                                                      v__do_e_9
                                                                                                                                                    ];
                                                                                                                                                  }
                                                                                                                                                  case 4: {
                                                                                                                                                    const v_s11 = s[1];
                                                                                                                                                    return ((
                                                                                                                                                      s
                                                                                                                                                    ) => {
                                                                                                                                                      switch (s[0]) {
                                                                                                                                                        case 3: {
                                                                                                                                                          const v__do_e_8 = s[1];
                                                                                                                                                          return [
                                                                                                                                                            3,
                                                                                                                                                            v__do_e_8
                                                                                                                                                          ];
                                                                                                                                                        }
                                                                                                                                                        case 4: {
                                                                                                                                                          const v_s12 = s[1];
                                                                                                                                                          return ((
                                                                                                                                                            s
                                                                                                                                                          ) => {
                                                                                                                                                            switch (s[0]) {
                                                                                                                                                              case 3: {
                                                                                                                                                                const v__do_e_7 = s[1];
                                                                                                                                                                return [
                                                                                                                                                                  3,
                                                                                                                                                                  v__do_e_7
                                                                                                                                                                ];
                                                                                                                                                              }
                                                                                                                                                              case 4: {
                                                                                                                                                                const v_s13 = s[1];
                                                                                                                                                                return ((
                                                                                                                                                                  s
                                                                                                                                                                ) => {
                                                                                                                                                                  switch (s[0]) {
                                                                                                                                                                    case 3: {
                                                                                                                                                                      const v__do_e_6 = s[1];
                                                                                                                                                                      return [
                                                                                                                                                                        3,
                                                                                                                                                                        v__do_e_6
                                                                                                                                                                      ];
                                                                                                                                                                    }
                                                                                                                                                                    case 4: {
                                                                                                                                                                      const v_s14 = s[1];
                                                                                                                                                                      return ((
                                                                                                                                                                        s
                                                                                                                                                                      ) => {
                                                                                                                                                                        switch (s[0]) {
                                                                                                                                                                          case 3: {
                                                                                                                                                                            const v__do_e_5 = s[1];
                                                                                                                                                                            return [
                                                                                                                                                                              3,
                                                                                                                                                                              v__do_e_5
                                                                                                                                                                            ];
                                                                                                                                                                          }
                                                                                                                                                                          case 4: {
                                                                                                                                                                            const v_s15 = s[1];
                                                                                                                                                                            return ((
                                                                                                                                                                              s
                                                                                                                                                                            ) => {
                                                                                                                                                                              switch (s[0]) {
                                                                                                                                                                                case 3: {
                                                                                                                                                                                  const v__do_e_4 = s[1];
                                                                                                                                                                                  return [
                                                                                                                                                                                    3,
                                                                                                                                                                                    v__do_e_4
                                                                                                                                                                                  ];
                                                                                                                                                                                }
                                                                                                                                                                                case 4: {
                                                                                                                                                                                  const v_s16 = s[1];
                                                                                                                                                                                  return ((
                                                                                                                                                                                    s
                                                                                                                                                                                  ) => {
                                                                                                                                                                                    switch (s[0]) {
                                                                                                                                                                                      case 3: {
                                                                                                                                                                                        const v__do_e_3 = s[1];
                                                                                                                                                                                        return [
                                                                                                                                                                                          3,
                                                                                                                                                                                          v__do_e_3
                                                                                                                                                                                        ];
                                                                                                                                                                                      }
                                                                                                                                                                                      case 4: {
                                                                                                                                                                                        const v_s17 = s[1];
                                                                                                                                                                                        return ((
                                                                                                                                                                                          s
                                                                                                                                                                                        ) => {
                                                                                                                                                                                          switch (s[0]) {
                                                                                                                                                                                            case 3: {
                                                                                                                                                                                              const v__do_e_2 = s[1];
                                                                                                                                                                                              return [
                                                                                                                                                                                                3,
                                                                                                                                                                                                v__do_e_2
                                                                                                                                                                                              ];
                                                                                                                                                                                            }
                                                                                                                                                                                            case 4: {
                                                                                                                                                                                              const v_s18 = s[1];
                                                                                                                                                                                              return ((
                                                                                                                                                                                                s
                                                                                                                                                                                              ) => {
                                                                                                                                                                                                switch (s[0]) {
                                                                                                                                                                                                  case 3: {
                                                                                                                                                                                                    const v__do_e_1 = s[1];
                                                                                                                                                                                                    return [
                                                                                                                                                                                                      3,
                                                                                                                                                                                                      v__do_e_1
                                                                                                                                                                                                    ];
                                                                                                                                                                                                  }
                                                                                                                                                                                                  case 4: {
                                                                                                                                                                                                    const v_s19 = s[1];
                                                                                                                                                                                                    return ((
                                                                                                                                                                                                      s
                                                                                                                                                                                                    ) => {
                                                                                                                                                                                                      switch (s[0]) {
                                                                                                                                                                                                        case 3: {
                                                                                                                                                                                                          const v__do_e_0 = s[1];
                                                                                                                                                                                                          return [
                                                                                                                                                                                                            3,
                                                                                                                                                                                                            v__do_e_0
                                                                                                                                                                                                          ];
                                                                                                                                                                                                        }
                                                                                                                                                                                                        case 4: {
                                                                                                                                                                                                          const v_s20 = s[1];
                                                                                                                                                                                                          return __concat(
                                                                                                                                                                                                            v_s20,
                                                                                                                                                                                                            v_l
                                                                                                                                                                                                          );
                                                                                                                                                                                                        }
                                                                                                                                                                                                      }
                                                                                                                                                                                                    })(
                                                                                                                                                                                                      __concat(
                                                                                                                                                                                                        v_s19,
                                                                                                                                                                                                        ", "
                                                                                                                                                                                                      )
                                                                                                                                                                                                    );
                                                                                                                                                                                                  }
                                                                                                                                                                                                }
                                                                                                                                                                                              })(
                                                                                                                                                                                                __concat(
                                                                                                                                                                                                  v_s18,
                                                                                                                                                                                                  v_k
                                                                                                                                                                                                )
                                                                                                                                                                                              );
                                                                                                                                                                                            }
                                                                                                                                                                                          }
                                                                                                                                                                                        })(
                                                                                                                                                                                          __concat(
                                                                                                                                                                                            v_s17,
                                                                                                                                                                                            ", "
                                                                                                                                                                                          )
                                                                                                                                                                                        );
                                                                                                                                                                                      }
                                                                                                                                                                                    }
                                                                                                                                                                                  })(
                                                                                                                                                                                    __concat(
                                                                                                                                                                                      v_s16,
                                                                                                                                                                                      v_j
                                                                                                                                                                                    )
                                                                                                                                                                                  );
                                                                                                                                                                                }
                                                                                                                                                                              }
                                                                                                                                                                            })(
                                                                                                                                                                              __concat(
                                                                                                                                                                                v_s15,
                                                                                                                                                                                ", "
                                                                                                                                                                              )
                                                                                                                                                                            );
                                                                                                                                                                          }
                                                                                                                                                                        }
                                                                                                                                                                      })(
                                                                                                                                                                        __concat(
                                                                                                                                                                          v_s14,
                                                                                                                                                                          v_i
                                                                                                                                                                        )
                                                                                                                                                                      );
                                                                                                                                                                    }
                                                                                                                                                                  }
                                                                                                                                                                })(
                                                                                                                                                                  __concat(
                                                                                                                                                                    v_s13,
                                                                                                                                                                    ", "
                                                                                                                                                                  )
                                                                                                                                                                );
                                                                                                                                                              }
                                                                                                                                                            }
                                                                                                                                                          })(
                                                                                                                                                            __concat(
                                                                                                                                                              v_s12,
                                                                                                                                                              v_h
                                                                                                                                                            )
                                                                                                                                                          );
                                                                                                                                                        }
                                                                                                                                                      }
                                                                                                                                                    })(
                                                                                                                                                      __concat(
                                                                                                                                                        v_s11,
                                                                                                                                                        ", "
                                                                                                                                                      )
                                                                                                                                                    );
                                                                                                                                                  }
                                                                                                                                                }
                                                                                                                                              })(
                                                                                                                                                __concat(
                                                                                                                                                  v_s10,
                                                                                                                                                  v_g
                                                                                                                                                )
                                                                                                                                              );
                                                                                                                                            }
                                                                                                                                          }
                                                                                                                                        })(
                                                                                                                                          __concat(
                                                                                                                                            v_s9,
                                                                                                                                            ", "
                                                                                                                                          )
                                                                                                                                        );
                                                                                                                                      }
                                                                                                                                    }
                                                                                                                                  })(
                                                                                                                                    __concat(
                                                                                                                                      v_s8,
                                                                                                                                      v_f
                                                                                                                                    )
                                                                                                                                  );
                                                                                                                                }
                                                                                                                              }
                                                                                                                            })(
                                                                                                                              __concat(
                                                                                                                                v_s7,
                                                                                                                                ", "
                                                                                                                              )
                                                                                                                            );
                                                                                                                          }
                                                                                                                        }
                                                                                                                      })(
                                                                                                                        __concat(
                                                                                                                          v_s6,
                                                                                                                          v_e
                                                                                                                        )
                                                                                                                      );
                                                                                                                    }
                                                                                                                  }
                                                                                                                })(
                                                                                                                  __concat(
                                                                                                                    v_s5,
                                                                                                                    ", "
                                                                                                                  )
                                                                                                                );
                                                                                                              }
                                                                                                            }
                                                                                                          })(
                                                                                                            __concat(
                                                                                                              v_s4,
                                                                                                              v_d
                                                                                                            )
                                                                                                          );
                                                                                                        }
                                                                                                      }
                                                                                                    })(
                                                                                                      __concat(
                                                                                                        v_s3,
                                                                                                        ", "
                                                                                                      )
                                                                                                    );
                                                                                                  }
                                                                                                }
                                                                                              })(
                                                                                                __concat(
                                                                                                  v_s2,
                                                                                                  v_c
                                                                                                )
                                                                                              );
                                                                                            }
                                                                                          }
                                                                                        })(
                                                                                          __concat(
                                                                                            v_s1,
                                                                                            ", "
                                                                                          )
                                                                                        );
                                                                                      }
                                                                                    }
                                                                                  })(
                                                                                    __concat(
                                                                                      v_s0,
                                                                                      v_b
                                                                                    )
                                                                                  );
                                                                                }
                                                                              }
                                                                            })(
                                                                              __concat(
                                                                                v_a,
                                                                                ", "
                                                                              )
                                                                            );
                                                                          }
                                                                        }
                                                                      })(
                                                                        v_render(
                                                                          __parseInt32(
                                                                            "12abc"
                                                                          )
                                                                        )
                                                                      );
                                                                    }
                                                                  }
                                                                })(
                                                                  v_render(
                                                                    __parseInt32(
                                                                      " 42"
                                                                    )
                                                                  )
                                                                );
                                                              }
                                                            }
                                                          })(
                                                            v_render(
                                                              __parseInt32(
                                                                "+42"
                                                              )
                                                            )
                                                          );
                                                        }
                                                      }
                                                    })(
                                                      v_render(
                                                        __parseInt32("-")
                                                      )
                                                    );
                                                  }
                                                }
                                              })(v_render(__parseInt32("")));
                                            }
                                          }
                                        })(
                                          v_render(__parseInt32("-2147483649"))
                                        );
                                      }
                                    }
                                  })(v_render(__parseInt32("2147483648")));
                                }
                              }
                            })(v_render(__parseInt32("-2147483648")));
                          }
                        }
                      })(v_render(__parseInt32("2147483647")));
                    }
                  }
                })(v_render(__parseInt32("0")));
              }
            }
          })(v_render(__parseInt32("-42")));
        }
      }
    })(v_render(__parseInt32("42")))
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
