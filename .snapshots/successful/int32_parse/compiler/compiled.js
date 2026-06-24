"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __parseInt32 = s => {
    if (!/^-?[0-9]+$/.test(s)) {
      return [3, [22]];
    }
    const n = Number(s);
    if (n < -2147483648 || n > 2147483647) {
      return [3, [22]];
    }
    return [4, n | 0];
  };

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$inl3$r = __parseInt32("42");
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__32 = s[1];
        return [3, v_$do__e__32];
      }
      case 4: {
        const v_a = s[1];
        const v_$inl6$r = __parseInt32("-42");
        {
          const __s = (s => {
            switch (s[0]) {
              case 3: {
                return [4, "err"];
              }
              case 4: {
                return __concat("ok:", String(v_$inl6$r[1]));
              }
            }
          })(v_$inl6$r);
          switch (__s[0]) {
            case 3: {
              const v_$do__e__31 = __s[1];
              return [3, v_$do__e__31];
            }
            case 4: {
              const v_b = __s[1];
              const v_$inl9$r = __parseInt32("0");
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 3: {
                      return [4, "err"];
                    }
                    case 4: {
                      return __concat("ok:", String(v_$inl9$r[1]));
                    }
                  }
                })(v_$inl9$r);
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__30 = __s[1];
                    return [3, v_$do__e__30];
                  }
                  case 4: {
                    const v_c = __s[1];
                    const v_$inl12$r = __parseInt32("2147483647");
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 3: {
                            return [4, "err"];
                          }
                          case 4: {
                            return __concat("ok:", String(v_$inl12$r[1]));
                          }
                        }
                      })(v_$inl12$r);
                      switch (__s[0]) {
                        case 3: {
                          const v_$do__e__29 = __s[1];
                          return [3, v_$do__e__29];
                        }
                        case 4: {
                          const v_d = __s[1];
                          const v_$inl15$r = __parseInt32("-2147483648");
                          {
                            const __s = (s => {
                              switch (s[0]) {
                                case 3: {
                                  return [4, "err"];
                                }
                                case 4: {
                                  return __concat("ok:", String(v_$inl15$r[1]));
                                }
                              }
                            })(v_$inl15$r);
                            switch (__s[0]) {
                              case 3: {
                                const v_$do__e__28 = __s[1];
                                return [3, v_$do__e__28];
                              }
                              case 4: {
                                const v_e = __s[1];
                                const v_$inl18$r = __parseInt32("2147483648");
                                {
                                  const __s = (s => {
                                    switch (s[0]) {
                                      case 3: {
                                        return [4, "err"];
                                      }
                                      case 4: {
                                        return __concat(
                                          "ok:",
                                          String(v_$inl18$r[1])
                                        );
                                      }
                                    }
                                  })(v_$inl18$r);
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$do__e__27 = __s[1];
                                      return [3, v_$do__e__27];
                                    }
                                    case 4: {
                                      const v_f = __s[1];
                                      const v_$inl21$r = __parseInt32(
                                        "-2147483649"
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
                                                String(v_$inl21$r[1])
                                              );
                                            }
                                          }
                                        })(v_$inl21$r);
                                        switch (__s[0]) {
                                          case 3: {
                                            const v_$do__e__26 = __s[1];
                                            return [3, v_$do__e__26];
                                          }
                                          case 4: {
                                            const v_g = __s[1];
                                            const v_$inl24$r = __parseInt32("");
                                            {
                                              const __s = (s => {
                                                switch (s[0]) {
                                                  case 3: {
                                                    return [4, "err"];
                                                  }
                                                  case 4: {
                                                    return __concat(
                                                      "ok:",
                                                      String(v_$inl24$r[1])
                                                    );
                                                  }
                                                }
                                              })(v_$inl24$r);
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v_$do__e__25 = __s[1];
                                                  return [3, v_$do__e__25];
                                                }
                                                case 4: {
                                                  const v_h = __s[1];
                                                  const v_$inl27$r = __parseInt32(
                                                    "-"
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
                                                              v_$inl27$r[1]
                                                            )
                                                          );
                                                        }
                                                      }
                                                    })(v_$inl27$r);
                                                    switch (__s[0]) {
                                                      case 3: {
                                                        const v_$do__e__24 = __s[1];
                                                        return [
                                                          3,
                                                          v_$do__e__24
                                                        ];
                                                      }
                                                      case 4: {
                                                        const v_i = __s[1];
                                                        const v_$inl30$r = __parseInt32(
                                                          "+42"
                                                        );
                                                        {
                                                          const __s = (s => {
                                                            switch (s[0]) {
                                                              case 3: {
                                                                return [
                                                                  4,
                                                                  "err"
                                                                ];
                                                              }
                                                              case 4: {
                                                                return __concat(
                                                                  "ok:",
                                                                  String(
                                                                    v_$inl30$r[1]
                                                                  )
                                                                );
                                                              }
                                                            }
                                                          })(v_$inl30$r);
                                                          switch (__s[0]) {
                                                            case 3: {
                                                              const v_$do__e__23 = __s[1];
                                                              return [
                                                                3,
                                                                v_$do__e__23
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v_j = __s[1];
                                                              const v_$inl33$r = __parseInt32(
                                                                " 42"
                                                              );
                                                              {
                                                                const __s = (s => {
                                                                  switch (s[0]) {
                                                                    case 3: {
                                                                      return [
                                                                        4,
                                                                        "err"
                                                                      ];
                                                                    }
                                                                    case 4: {
                                                                      return __concat(
                                                                        "ok:",
                                                                        String(
                                                                          v_$inl33$r[1]
                                                                        )
                                                                      );
                                                                    }
                                                                  }
                                                                })(v_$inl33$r);
                                                                switch (__s[0]) {
                                                                  case 3: {
                                                                    const v_$do__e__22 = __s[1];
                                                                    return [
                                                                      3,
                                                                      v_$do__e__22
                                                                    ];
                                                                  }
                                                                  case 4: {
                                                                    const v_k = __s[1];
                                                                    const v_$inl36$r = __parseInt32(
                                                                      "12abc"
                                                                    );
                                                                    {
                                                                      const __s = (s => {
                                                                        switch (s[0]) {
                                                                          case 3: {
                                                                            return [
                                                                              4,
                                                                              "err"
                                                                            ];
                                                                          }
                                                                          case 4: {
                                                                            return __concat(
                                                                              "ok:",
                                                                              String(
                                                                                v_$inl36$r[1]
                                                                              )
                                                                            );
                                                                          }
                                                                        }
                                                                      })(
                                                                        v_$inl36$r
                                                                      );
                                                                      switch (__s[0]) {
                                                                        case 3: {
                                                                          const v_$do__e__21 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v_$do__e__21
                                                                          ];
                                                                        }
                                                                        case 4: {
                                                                          const v_l = __s[1];
                                                                          {
                                                                            const __s = __concat(
                                                                              v_a,
                                                                              ", "
                                                                            );
                                                                            switch (__s[0]) {
                                                                              case 3: {
                                                                                const v_$do__e__20 = __s[1];
                                                                                return [
                                                                                  3,
                                                                                  v_$do__e__20
                                                                                ];
                                                                              }
                                                                              case 4: {
                                                                                const v_s0 = __s[1];
                                                                                {
                                                                                  const __s = __concat(
                                                                                    v_s0,
                                                                                    v_b
                                                                                  );
                                                                                  switch (__s[0]) {
                                                                                    case 3: {
                                                                                      const v_$do__e__19 = __s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v_$do__e__19
                                                                                      ];
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
                                                                                            const v_$do__e__18 = __s[1];
                                                                                            return [
                                                                                              3,
                                                                                              v_$do__e__18
                                                                                            ];
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
                                                                                                  const v_$do__e__17 = __s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v_$do__e__17
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
                                                                                                        const v_$do__e__16 = __s[1];
                                                                                                        return [
                                                                                                          3,
                                                                                                          v_$do__e__16
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
                                                                                                              const v_$do__e__15 = __s[1];
                                                                                                              return [
                                                                                                                3,
                                                                                                                v_$do__e__15
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
                                                                                                                    const v_$do__e__14 = __s[1];
                                                                                                                    return [
                                                                                                                      3,
                                                                                                                      v_$do__e__14
                                                                                                                    ];
                                                                                                                  }
                                                                                                                  case 4: {
                                                                                                                    const v_s6 = __s[1];
                                                                                                                    {
                                                                                                                      const __s = __concat(
                                                                                                                        v_s6,
                                                                                                                        v_e
                                                                                                                      );
                                                                                                                      switch (__s[0]) {
                                                                                                                        case 3: {
                                                                                                                          const v_$do__e__13 = __s[1];
                                                                                                                          return [
                                                                                                                            3,
                                                                                                                            v_$do__e__13
                                                                                                                          ];
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
                                                                                                                                const v_$do__e__12 = __s[1];
                                                                                                                                return [
                                                                                                                                  3,
                                                                                                                                  v_$do__e__12
                                                                                                                                ];
                                                                                                                              }
                                                                                                                              case 4: {
                                                                                                                                const v_s8 = __s[1];
                                                                                                                                {
                                                                                                                                  const __s = __concat(
                                                                                                                                    v_s8,
                                                                                                                                    v_f
                                                                                                                                  );
                                                                                                                                  switch (__s[0]) {
                                                                                                                                    case 3: {
                                                                                                                                      const v_$do__e__11 = __s[1];
                                                                                                                                      return [
                                                                                                                                        3,
                                                                                                                                        v_$do__e__11
                                                                                                                                      ];
                                                                                                                                    }
                                                                                                                                    case 4: {
                                                                                                                                      const v_s9 = __s[1];
                                                                                                                                      {
                                                                                                                                        const __s = __concat(
                                                                                                                                          v_s9,
                                                                                                                                          ", "
                                                                                                                                        );
                                                                                                                                        switch (__s[0]) {
                                                                                                                                          case 3: {
                                                                                                                                            const v_$do__e__10 = __s[1];
                                                                                                                                            return [
                                                                                                                                              3,
                                                                                                                                              v_$do__e__10
                                                                                                                                            ];
                                                                                                                                          }
                                                                                                                                          case 4: {
                                                                                                                                            const v_s10 = __s[1];
                                                                                                                                            {
                                                                                                                                              const __s = __concat(
                                                                                                                                                v_s10,
                                                                                                                                                v_g
                                                                                                                                              );
                                                                                                                                              switch (__s[0]) {
                                                                                                                                                case 3: {
                                                                                                                                                  const v_$do__e__9 = __s[1];
                                                                                                                                                  return [
                                                                                                                                                    3,
                                                                                                                                                    v_$do__e__9
                                                                                                                                                  ];
                                                                                                                                                }
                                                                                                                                                case 4: {
                                                                                                                                                  const v_s11 = __s[1];
                                                                                                                                                  {
                                                                                                                                                    const __s = __concat(
                                                                                                                                                      v_s11,
                                                                                                                                                      ", "
                                                                                                                                                    );
                                                                                                                                                    switch (__s[0]) {
                                                                                                                                                      case 3: {
                                                                                                                                                        const v_$do__e__8 = __s[1];
                                                                                                                                                        return [
                                                                                                                                                          3,
                                                                                                                                                          v_$do__e__8
                                                                                                                                                        ];
                                                                                                                                                      }
                                                                                                                                                      case 4: {
                                                                                                                                                        const v_s12 = __s[1];
                                                                                                                                                        {
                                                                                                                                                          const __s = __concat(
                                                                                                                                                            v_s12,
                                                                                                                                                            v_h
                                                                                                                                                          );
                                                                                                                                                          switch (__s[0]) {
                                                                                                                                                            case 3: {
                                                                                                                                                              const v_$do__e__7 = __s[1];
                                                                                                                                                              return [
                                                                                                                                                                3,
                                                                                                                                                                v_$do__e__7
                                                                                                                                                              ];
                                                                                                                                                            }
                                                                                                                                                            case 4: {
                                                                                                                                                              const v_s13 = __s[1];
                                                                                                                                                              {
                                                                                                                                                                const __s = __concat(
                                                                                                                                                                  v_s13,
                                                                                                                                                                  ", "
                                                                                                                                                                );
                                                                                                                                                                switch (__s[0]) {
                                                                                                                                                                  case 3: {
                                                                                                                                                                    const v_$do__e__6 = __s[1];
                                                                                                                                                                    return [
                                                                                                                                                                      3,
                                                                                                                                                                      v_$do__e__6
                                                                                                                                                                    ];
                                                                                                                                                                  }
                                                                                                                                                                  case 4: {
                                                                                                                                                                    const v_s14 = __s[1];
                                                                                                                                                                    {
                                                                                                                                                                      const __s = __concat(
                                                                                                                                                                        v_s14,
                                                                                                                                                                        v_i
                                                                                                                                                                      );
                                                                                                                                                                      switch (__s[0]) {
                                                                                                                                                                        case 3: {
                                                                                                                                                                          const v_$do__e__5 = __s[1];
                                                                                                                                                                          return [
                                                                                                                                                                            3,
                                                                                                                                                                            v_$do__e__5
                                                                                                                                                                          ];
                                                                                                                                                                        }
                                                                                                                                                                        case 4: {
                                                                                                                                                                          const v_s15 = __s[1];
                                                                                                                                                                          {
                                                                                                                                                                            const __s = __concat(
                                                                                                                                                                              v_s15,
                                                                                                                                                                              ", "
                                                                                                                                                                            );
                                                                                                                                                                            switch (__s[0]) {
                                                                                                                                                                              case 3: {
                                                                                                                                                                                const v_$do__e__4 = __s[1];
                                                                                                                                                                                return [
                                                                                                                                                                                  3,
                                                                                                                                                                                  v_$do__e__4
                                                                                                                                                                                ];
                                                                                                                                                                              }
                                                                                                                                                                              case 4: {
                                                                                                                                                                                const v_s16 = __s[1];
                                                                                                                                                                                {
                                                                                                                                                                                  const __s = __concat(
                                                                                                                                                                                    v_s16,
                                                                                                                                                                                    v_j
                                                                                                                                                                                  );
                                                                                                                                                                                  switch (__s[0]) {
                                                                                                                                                                                    case 3: {
                                                                                                                                                                                      const v_$do__e__3 = __s[1];
                                                                                                                                                                                      return [
                                                                                                                                                                                        3,
                                                                                                                                                                                        v_$do__e__3
                                                                                                                                                                                      ];
                                                                                                                                                                                    }
                                                                                                                                                                                    case 4: {
                                                                                                                                                                                      const v_s17 = __s[1];
                                                                                                                                                                                      {
                                                                                                                                                                                        const __s = __concat(
                                                                                                                                                                                          v_s17,
                                                                                                                                                                                          ", "
                                                                                                                                                                                        );
                                                                                                                                                                                        switch (__s[0]) {
                                                                                                                                                                                          case 3: {
                                                                                                                                                                                            const v_$do__e__2 = __s[1];
                                                                                                                                                                                            return [
                                                                                                                                                                                              3,
                                                                                                                                                                                              v_$do__e__2
                                                                                                                                                                                            ];
                                                                                                                                                                                          }
                                                                                                                                                                                          case 4: {
                                                                                                                                                                                            const v_s18 = __s[1];
                                                                                                                                                                                            {
                                                                                                                                                                                              const __s = __concat(
                                                                                                                                                                                                v_s18,
                                                                                                                                                                                                v_k
                                                                                                                                                                                              );
                                                                                                                                                                                              switch (__s[0]) {
                                                                                                                                                                                                case 3: {
                                                                                                                                                                                                  const v_$do__e__1 = __s[1];
                                                                                                                                                                                                  return [
                                                                                                                                                                                                    3,
                                                                                                                                                                                                    v_$do__e__1
                                                                                                                                                                                                  ];
                                                                                                                                                                                                }
                                                                                                                                                                                                case 4: {
                                                                                                                                                                                                  const v_s19 = __s[1];
                                                                                                                                                                                                  {
                                                                                                                                                                                                    const __s = __concat(
                                                                                                                                                                                                      v_s19,
                                                                                                                                                                                                      ", "
                                                                                                                                                                                                    );
                                                                                                                                                                                                    switch (__s[0]) {
                                                                                                                                                                                                      case 3: {
                                                                                                                                                                                                        const v_$do__e__0 = __s[1];
                                                                                                                                                                                                        return [
                                                                                                                                                                                                          3,
                                                                                                                                                                                                          v_$do__e__0
                                                                                                                                                                                                        ];
                                                                                                                                                                                                      }
                                                                                                                                                                                                      case 4: {
                                                                                                                                                                                                        const v_s20 = __s[1];
                                                                                                                                                                                                        return __concat(
                                                                                                                                                                                                          v_s20,
                                                                                                                                                                                                          v_l
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
          return __concat("ok:", String(v_$inl3$r[1]));
        }
      }
    })(v_$inl3$r)
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 20: {
          return v_$x;
        }
        case 21: {
          const v_$pk__21 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__21;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$0(
            v_$k,
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [21, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 22: {
          return v_$x;
        }
        case 23: {
          const v_$pk__23 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__23;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [23, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl39$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl39$x[1]];
          }
          case 4: {
            return [5, v_$inl39$x[1]];
          }
        }
      })(v_$inl39$x),
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
