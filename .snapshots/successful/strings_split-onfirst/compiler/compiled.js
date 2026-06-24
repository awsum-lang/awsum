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
          const v_$inl0$eff = __print(v_io[1]);
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
              const v_$inl1$$do__e__2 = __s[1];
              return [3, v_$inl1$$do__e__2];
            }
            case 4: {
              const v_$inl2$s0 = __s[1];
              {
                const __s = __concat(v_$inl2$s0, "|");
                switch (__s[0]) {
                  case 3: {
                    const v_$inl3$$do__e__1 = __s[1];
                    return [3, v_$inl3$$do__e__1];
                  }
                  case 4: {
                    const v_$inl4$s1 = __s[1];
                    {
                      const __s = __concat(v_$inl4$s1, v_t[2]);
                      switch (__s[0]) {
                        case 3: {
                          const v_$inl5$$do__e__0 = __s[1];
                          return [3, v_$inl5$$do__e__0];
                        }
                        case 4: {
                          const v_$inl6$s2 = __s[1];
                          return __concat(v_$inl6$s2, ")");
                        }
                      }
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
        const v_$do__e__23 = s[1];
        return [3, v_$do__e__23];
      }
      case 4: {
        const v_a = s[1];
        {
          const __s = v_render(__splitOnFirst("::", "user::42::admin"));
          switch (__s[0]) {
            case 3: {
              const v_$do__e__22 = __s[1];
              return [3, v_$do__e__22];
            }
            case 4: {
              const v_b = __s[1];
              {
                const __s = v_render(__splitOnFirst("x", "abc"));
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__21 = __s[1];
                    return [3, v_$do__e__21];
                  }
                  case 4: {
                    const v_c = __s[1];
                    {
                      const __s = v_render(__splitOnFirst("", "abc"));
                      switch (__s[0]) {
                        case 3: {
                          const v_$do__e__20 = __s[1];
                          return [3, v_$do__e__20];
                        }
                        case 4: {
                          const v_d = __s[1];
                          {
                            const __s = v_render(__splitOnFirst(":", ":foo"));
                            switch (__s[0]) {
                              case 3: {
                                const v_$do__e__19 = __s[1];
                                return [3, v_$do__e__19];
                              }
                              case 4: {
                                const v_e = __s[1];
                                {
                                  const __s = v_render(
                                    __splitOnFirst(":", "foo:")
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$do__e__18 = __s[1];
                                      return [3, v_$do__e__18];
                                    }
                                    case 4: {
                                      const v_f = __s[1];
                                      {
                                        const __s = v_render(
                                          __splitOnFirst("abc", "abc")
                                        );
                                        switch (__s[0]) {
                                          case 3: {
                                            const v_$do__e__17 = __s[1];
                                            return [3, v_$do__e__17];
                                          }
                                          case 4: {
                                            const v_g = __s[1];
                                            {
                                              const __s = v_render(
                                                __splitOnFirst("abcde", "ab")
                                              );
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v_$do__e__16 = __s[1];
                                                  return [3, v_$do__e__16];
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
                                                        const v_$do__e__15 = __s[1];
                                                        return [
                                                          3,
                                                          v_$do__e__15
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
                                                              const v_$do__e__14 = __s[1];
                                                              return [
                                                                3,
                                                                v_$do__e__14
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
                                                                    const v_$do__e__13 = __s[1];
                                                                    return [
                                                                      3,
                                                                      v_$do__e__13
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
                                                                          const v_$do__e__12 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v_$do__e__12
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
                                                                                const v_$do__e__11 = __s[1];
                                                                                return [
                                                                                  3,
                                                                                  v_$do__e__11
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
                                                                                      const v_$do__e__10 = __s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v_$do__e__10
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
                                                                                            const v_$do__e__9 = __s[1];
                                                                                            return [
                                                                                              3,
                                                                                              v_$do__e__9
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
                                                                                                  const v_$do__e__8 = __s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v_$do__e__8
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
                                                                                                        const v_$do__e__7 = __s[1];
                                                                                                        return [
                                                                                                          3,
                                                                                                          v_$do__e__7
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
                                                                                                              const v_$do__e__6 = __s[1];
                                                                                                              return [
                                                                                                                3,
                                                                                                                v_$do__e__6
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
                                                                                                                    const v_$do__e__5 = __s[1];
                                                                                                                    return [
                                                                                                                      3,
                                                                                                                      v_$do__e__5
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
                                                                                                                          const v_$do__e__4 = __s[1];
                                                                                                                          return [
                                                                                                                            3,
                                                                                                                            v_$do__e__4
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
                                                                                                                                const v_$do__e__3 = __s[1];
                                                                                                                                return [
                                                                                                                                  3,
                                                                                                                                  v_$do__e__3
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

  const v_$inl9$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl9$x[1]];
          }
          case 4: {
            return [5, v_$inl9$x[1]];
          }
        }
      })(v_$inl9$x),
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
