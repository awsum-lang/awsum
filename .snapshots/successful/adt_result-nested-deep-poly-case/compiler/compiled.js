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
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$inl3$r = [24, [24, [24, "1"]]];
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__12 = s[1];
        return [3, v_$do__e__12];
      }
      case 4: {
        const v_s0 = s[1];
        {
          const v_$inl6$r = [24, [24, [25, "2"]]];
          const __s = __concat(
            v_s0,
            (s => {
              switch (s[0]) {
                case 24: {
                  const v_$inl4$inner2 = s[1];
                  return v_$inl4$inner2[1];
                }
                case 25: {
                  const v_$inl5$inner2 = s[1];
                  return v_$inl5$inner2[1];
                }
              }
            })(v_$inl6$r[1])
          );
          switch (__s[0]) {
            case 3: {
              const v_$do__e__11 = __s[1];
              return [3, v_$do__e__11];
            }
            case 4: {
              const v_s1 = __s[1];
              {
                const __s = __concat(v_s1, ",");
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__10 = __s[1];
                    return [3, v_$do__e__10];
                  }
                  case 4: {
                    const v_s2 = __s[1];
                    {
                      const v_$inl9$r = [24, [25, [24, "3"]]];
                      const __s = __concat(
                        v_s2,
                        (s => {
                          switch (s[0]) {
                            case 24: {
                              const v_$inl7$inner2 = s[1];
                              return v_$inl7$inner2[1];
                            }
                            case 25: {
                              const v_$inl8$inner2 = s[1];
                              return v_$inl8$inner2[1];
                            }
                          }
                        })(v_$inl9$r[1])
                      );
                      switch (__s[0]) {
                        case 3: {
                          const v_$do__e__9 = __s[1];
                          return [3, v_$do__e__9];
                        }
                        case 4: {
                          const v_s3 = __s[1];
                          {
                            const __s = __concat(v_s3, ",");
                            switch (__s[0]) {
                              case 3: {
                                const v_$do__e__8 = __s[1];
                                return [3, v_$do__e__8];
                              }
                              case 4: {
                                const v_s4 = __s[1];
                                {
                                  const v_$inl12$r = [24, [25, [25, "4"]]];
                                  const __s = __concat(
                                    v_s4,
                                    (s => {
                                      switch (s[0]) {
                                        case 24: {
                                          const v_$inl10$inner2 = s[1];
                                          return v_$inl10$inner2[1];
                                        }
                                        case 25: {
                                          const v_$inl11$inner2 = s[1];
                                          return v_$inl11$inner2[1];
                                        }
                                      }
                                    })(v_$inl12$r[1])
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$do__e__7 = __s[1];
                                      return [3, v_$do__e__7];
                                    }
                                    case 4: {
                                      const v_s5 = __s[1];
                                      {
                                        const __s = __concat(v_s5, ",");
                                        switch (__s[0]) {
                                          case 3: {
                                            const v_$do__e__6 = __s[1];
                                            return [3, v_$do__e__6];
                                          }
                                          case 4: {
                                            const v_s6 = __s[1];
                                            {
                                              const v_$inl15$r = [
                                                25,
                                                [24, [24, "5"]]
                                              ];
                                              const __s = __concat(
                                                v_s6,
                                                (s => {
                                                  switch (s[0]) {
                                                    case 24: {
                                                      const v_$inl13$inner2 = s[1];
                                                      return v_$inl13$inner2[1];
                                                    }
                                                    case 25: {
                                                      const v_$inl14$inner2 = s[1];
                                                      return v_$inl14$inner2[1];
                                                    }
                                                  }
                                                })(v_$inl15$r[1])
                                              );
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v_$do__e__5 = __s[1];
                                                  return [3, v_$do__e__5];
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
                                                        const v_$do__e__4 = __s[1];
                                                        return [3, v_$do__e__4];
                                                      }
                                                      case 4: {
                                                        const v_s8 = __s[1];
                                                        {
                                                          const v_$inl18$r = [
                                                            25,
                                                            [24, [25, "6"]]
                                                          ];
                                                          const __s = __concat(
                                                            v_s8,
                                                            (s => {
                                                              switch (s[0]) {
                                                                case 24: {
                                                                  const v_$inl16$inner2 = s[1];
                                                                  return v_$inl16$inner2[1];
                                                                }
                                                                case 25: {
                                                                  const v_$inl17$inner2 = s[1];
                                                                  return v_$inl17$inner2[1];
                                                                }
                                                              }
                                                            })(v_$inl18$r[1])
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
                                                              const v_s9 = __s[1];
                                                              {
                                                                const __s = __concat(
                                                                  v_s9,
                                                                  ","
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
                                                                    const v_s10 = __s[1];
                                                                    {
                                                                      const v_$inl21$r = [
                                                                        25,
                                                                        [
                                                                          25,
                                                                          [
                                                                            24,
                                                                            "7"
                                                                          ]
                                                                        ]
                                                                      ];
                                                                      const __s = __concat(
                                                                        v_s10,
                                                                        (s => {
                                                                          switch (s[0]) {
                                                                            case 24: {
                                                                              const v_$inl19$inner2 = s[1];
                                                                              return v_$inl19$inner2[1];
                                                                            }
                                                                            case 25: {
                                                                              const v_$inl20$inner2 = s[1];
                                                                              return v_$inl20$inner2[1];
                                                                            }
                                                                          }
                                                                        })(
                                                                          v_$inl21$r[1]
                                                                        )
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
                                                                          const v_s11 = __s[1];
                                                                          {
                                                                            const __s = __concat(
                                                                              v_s11,
                                                                              ","
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
                                                                                const v_s12 = __s[1];
                                                                                const v_$inl24$r = [
                                                                                  25,
                                                                                  [
                                                                                    25,
                                                                                    [
                                                                                      25,
                                                                                      "8"
                                                                                    ]
                                                                                  ]
                                                                                ];
                                                                                return __concat(
                                                                                  v_s12,
                                                                                  (s => {
                                                                                    switch (s[0]) {
                                                                                      case 24: {
                                                                                        const v_$inl22$inner2 = s[1];
                                                                                        return v_$inl22$inner2[1];
                                                                                      }
                                                                                      case 25: {
                                                                                        const v_$inl23$inner2 = s[1];
                                                                                        return v_$inl23$inner2[1];
                                                                                      }
                                                                                    }
                                                                                  })(
                                                                                    v_$inl24$r[1]
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
      (s => {
        switch (s[0]) {
          case 24: {
            const v_$inl1$inner2 = s[1];
            return v_$inl1$inner2[1];
          }
          case 25: {
            const v_$inl2$inner2 = s[1];
            return v_$inl2$inner2[1];
          }
        }
      })(v_$inl3$r[1]),
      ","
    )
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 26: {
          return v_$x;
        }
        case 27: {
          const v_$pk__27 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__27;
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
          v_$k = [27, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 28: {
          return v_$x;
        }
        case 29: {
          const v_$pk__29 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__29;
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
          v_$k = [29, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl27$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl27$x[1]];
          }
          case 4: {
            return [5, v_$inl27$x[1]];
          }
        }
      })(v_$inl27$x),
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
