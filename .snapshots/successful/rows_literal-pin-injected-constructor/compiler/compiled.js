"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const v_wrapped = [28, [1519763639, [26, 7 | 0]]];

  const v_seven = 7 | 0;

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

  const v_nested = [25, [1730259187, [24, 7 | 0]]];

  const v_named = [25, [1730259187, [24, v_seven]]];

  const v_direct = [24, 7 | 0];

  const v_bare = [25, [2711245919, 7 | 0]];

  const v_ascribed = [25, [1730259187, [24, 7 | 0]]];

  const v_$inl7$c = v_direct;
  const v_shown = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__4 = s[1];
        return [3, v_$do__e__4];
      }
      case 4: {
        const v_s1 = s[1];
        {
          const v_$inl21$c = v_bare;
          const __s = __addInt32(
            v_s1,
            (s => {
              switch (s[0]) {
                case 24: {
                  return v_$inl21$c[1];
                }
                case 25: {
                  const v_$inl16$x = s[1];
                  switch (v_$inl16$x[0]) {
                    case 1730259187: {
                      const v_$inl17$rest = v_$inl16$x[1];
                      switch (v_$inl17$rest[0]) {
                        case 24: {
                          return v_$inl17$rest[1];
                        }
                        case 25: {
                          return 0 | 0;
                        }
                      }
                    }
                    case 2711245919: {
                      return v_$inl16$x[1];
                    }
                  }
                }
              }
            })(v_$inl21$c)
          );
          switch (__s[0]) {
            case 3: {
              const v_$do__e__3 = __s[1];
              return [3, v_$do__e__3];
            }
            case 4: {
              const v_s2 = __s[1];
              {
                const v_$inl28$c = v_ascribed;
                const __s = __addInt32(
                  v_s2,
                  (s => {
                    switch (s[0]) {
                      case 24: {
                        return v_$inl28$c[1];
                      }
                      case 25: {
                        const v_$inl23$x = s[1];
                        switch (v_$inl23$x[0]) {
                          case 1730259187: {
                            const v_$inl24$rest = v_$inl23$x[1];
                            switch (v_$inl24$rest[0]) {
                              case 24: {
                                return v_$inl24$rest[1];
                              }
                              case 25: {
                                return 0 | 0;
                              }
                            }
                          }
                          case 2711245919: {
                            return v_$inl23$x[1];
                          }
                        }
                      }
                    }
                  })(v_$inl28$c)
                );
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__2 = __s[1];
                    return [3, v_$do__e__2];
                  }
                  case 4: {
                    const v_s3 = __s[1];
                    {
                      const v_$inl35$c = v_named;
                      const __s = __addInt32(
                        v_s3,
                        (s => {
                          switch (s[0]) {
                            case 24: {
                              return v_$inl35$c[1];
                            }
                            case 25: {
                              const v_$inl30$x = s[1];
                              switch (v_$inl30$x[0]) {
                                case 1730259187: {
                                  const v_$inl31$rest = v_$inl30$x[1];
                                  switch (v_$inl31$rest[0]) {
                                    case 24: {
                                      return v_$inl31$rest[1];
                                    }
                                    case 25: {
                                      return 0 | 0;
                                    }
                                  }
                                }
                                case 2711245919: {
                                  return v_$inl30$x[1];
                                }
                              }
                            }
                          }
                        })(v_$inl35$c)
                      );
                      switch (__s[0]) {
                        case 3: {
                          const v_$do__e__1 = __s[1];
                          return [3, v_$do__e__1];
                        }
                        case 4: {
                          const v_s4 = __s[1];
                          {
                            const __s = __addInt32(
                              v_s4,
                              (s => {
                                switch (s[0]) {
                                  case 28: {
                                    const v_$inl36$x = s[1];
                                    switch (v_$inl36$x[0]) {
                                      case 1519763639: {
                                        const v_$inl37$b = v_$inl36$x[1];
                                        return v_$inl37$b[1];
                                      }
                                      case 2711245919: {
                                        return v_$inl36$x[1];
                                      }
                                    }
                                  }
                                }
                              })(v_wrapped)
                            );
                            switch (__s[0]) {
                              case 3: {
                                const v_$do__e__0 = __s[1];
                                return [3, v_$do__e__0];
                              }
                              case 4: {
                                const v_s5 = __s[1];
                                return [4, String(v_s5)];
                              }
                            }
                          }
                        }
                      }
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
    __addInt32(
      (s => {
        switch (s[0]) {
          case 24: {
            return v_$inl7$c[1];
          }
          case 25: {
            const v_$inl2$x = s[1];
            switch (v_$inl2$x[0]) {
              case 1730259187: {
                const v_$inl3$rest = v_$inl2$x[1];
                switch (v_$inl3$rest[0]) {
                  case 24: {
                    return v_$inl3$rest[1];
                  }
                  case 25: {
                    return 0 | 0;
                  }
                }
              }
              case 2711245919: {
                return v_$inl2$x[1];
              }
            }
          }
        }
      })(v_$inl7$c),
      (() => {
        const v_$inl14$c = v_nested;
        return (s => {
          switch (s[0]) {
            case 24: {
              return v_$inl14$c[1];
            }
            case 25: {
              const v_$inl9$x = s[1];
              switch (v_$inl9$x[0]) {
                case 1730259187: {
                  const v_$inl10$rest = v_$inl9$x[1];
                  switch (v_$inl10$rest[0]) {
                    case 24: {
                      return v_$inl10$rest[1];
                    }
                    case 25: {
                      return 0 | 0;
                    }
                  }
                }
                case 2711245919: {
                  return v_$inl9$x[1];
                }
              }
            }
          }
        })(v_$inl14$c);
      })()
    )
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 29: {
          return v_$x;
        }
        case 30: {
          const v_$pk__30 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__30;
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
            (s => {
              switch (s[0]) {
                case 882564211: {
                  return [7, "OVERFLOW", [5, [0]]];
                }
                case 3768445577: {
                  return [7, "UNDERFLOW", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [30, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 31: {
          return v_$x;
        }
        case 32: {
          const v_$pk__32 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__32;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(
            v_$k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [32, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl43$x = v_shown;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl43$x[1]];
          }
          case 4: {
            return [5, v_$inl43$x[1]];
          }
        }
      })(v_$inl43$x),
      [31]
    ),
    [29]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
