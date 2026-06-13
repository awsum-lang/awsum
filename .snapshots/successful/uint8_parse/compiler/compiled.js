"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __parseUInt8 = s => {
    if (!/^[0-9]+$/.test(s)) {
      return [3, [22]];
    }
    const n = Number(s);
    if (n > 255) {
      return [3, [22]];
    }
    return [4, n & 0xFF];
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

  const main = (v__inl3_r =>
    (() => {
      let v__inl28_scrut;
      $join27: {
        const __s = (s => {
          switch (s[0]) {
            case 3: {
              return [4, "err"];
            }
            case 4: {
              return __concat("ok:", String(v__inl3_r[1]));
            }
          }
        })(v__inl3_r);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl28_scrut = (v__inl6_r =>
              (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_19 = s[1];
                    return [3, v__do_e_19];
                  }
                  case 4: {
                    const v_b = s[1];
                    const v__inl9_r = __parseUInt8("256");
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 3: {
                            return [4, "err"];
                          }
                          case 4: {
                            return __concat("ok:", String(v__inl9_r[1]));
                          }
                        }
                      })(v__inl9_r);
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_18 = __s[1];
                          return [3, v__do_e_18];
                        }
                        case 4: {
                          const v_c = __s[1];
                          const v__inl12_r = __parseUInt8("-1");
                          {
                            const __s = (s => {
                              switch (s[0]) {
                                case 3: {
                                  return [4, "err"];
                                }
                                case 4: {
                                  return __concat("ok:", String(v__inl12_r[1]));
                                }
                              }
                            })(v__inl12_r);
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_17 = __s[1];
                                return [3, v__do_e_17];
                              }
                              case 4: {
                                const v_d = __s[1];
                                const v__inl15_r = __parseUInt8("");
                                {
                                  const __s = (s => {
                                    switch (s[0]) {
                                      case 3: {
                                        return [4, "err"];
                                      }
                                      case 4: {
                                        return __concat(
                                          "ok:",
                                          String(v__inl15_r[1])
                                        );
                                      }
                                    }
                                  })(v__inl15_r);
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_16 = __s[1];
                                      return [3, v__do_e_16];
                                    }
                                    case 4: {
                                      const v_e = __s[1];
                                      const v__inl18_r = __parseUInt8("abc");
                                      {
                                        const __s = (s => {
                                          switch (s[0]) {
                                            case 3: {
                                              return [4, "err"];
                                            }
                                            case 4: {
                                              return __concat(
                                                "ok:",
                                                String(v__inl18_r[1])
                                              );
                                            }
                                          }
                                        })(v__inl18_r);
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_15 = __s[1];
                                            return [3, v__do_e_15];
                                          }
                                          case 4: {
                                            const v_f = __s[1];
                                            const v__inl21_r = __parseUInt8(
                                              " 5"
                                            );
                                            {
                                              const __s = (s => {
                                                switch (s[0]) {
                                                  case 3: {
                                                    return [4, "err"];
                                                  }
                                                  case 4: {
                                                    return __concat(
                                                      "ok:",
                                                      String(v__inl21_r[1])
                                                    );
                                                  }
                                                }
                                              })(v__inl21_r);
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__do_e_14 = __s[1];
                                                  return [3, v__do_e_14];
                                                }
                                                case 4: {
                                                  const v_g = __s[1];
                                                  const v__inl24_r = __parseUInt8(
                                                    "12a"
                                                  );
                                                  {
                                                    const __s = (s => {
                                                      switch (s[0]) {
                                                        case 3: {
                                                          return [4, "err"];
                                                        }
                                                        case 4: {
                                                          return __concat(
                                                            "ok:",
                                                            String(
                                                              v__inl24_r[1]
                                                            )
                                                          );
                                                        }
                                                      }
                                                    })(v__inl24_r);
                                                    switch (__s[0]) {
                                                      case 3: {
                                                        const v__do_e_13 = __s[1];
                                                        return [3, v__do_e_13];
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
                                                              const v__do_e_12 = __s[1];
                                                              return [
                                                                3,
                                                                v__do_e_12
                                                              ];
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
                                                                    const v__do_e_11 = __s[1];
                                                                    return [
                                                                      3,
                                                                      v__do_e_11
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
                                                                          const v__do_e_10 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v__do_e_10
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
                                                                                const v__do_e_9 = __s[1];
                                                                                return [
                                                                                  3,
                                                                                  v__do_e_9
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
                                                                                      const v__do_e_8 = __s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v__do_e_8
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
                                                                                            const v__do_e_7 = __s[1];
                                                                                            return [
                                                                                              3,
                                                                                              v__do_e_7
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
                                                                                                  const v__do_e_6 = __s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v__do_e_6
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
                                                                                                        const v__do_e_5 = __s[1];
                                                                                                        return [
                                                                                                          3,
                                                                                                          v__do_e_5
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
                                                                                                              const v__do_e_4 = __s[1];
                                                                                                              return [
                                                                                                                3,
                                                                                                                v__do_e_4
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
                                                                                                                    const v__do_e_3 = __s[1];
                                                                                                                    return [
                                                                                                                      3,
                                                                                                                      v__do_e_3
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
                                                                                                                          const v__do_e_2 = __s[1];
                                                                                                                          return [
                                                                                                                            3,
                                                                                                                            v__do_e_2
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
                                                                                                                                const v__do_e_1 = __s[1];
                                                                                                                                return [
                                                                                                                                  3,
                                                                                                                                  v__do_e_1
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
                                                                                                                                      const v__do_e_0 = __s[1];
                                                                                                                                      return [
                                                                                                                                        3,
                                                                                                                                        v__do_e_0
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
              })(
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [4, "err"];
                    }
                    case 4: {
                      return __concat("ok:", String(v__inl6_r[1]));
                    }
                  }
                })(v__inl6_r)
              ))(__parseUInt8("255"));
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
    })())(__parseUInt8("0"));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
