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

  const v_defaultRight = [4, [12, [2]]];

  const v_defaultJust = [12, [1]];

  const v_defaultBools = [26, [1], [26, [2], [25]]];

  const v_$apply$describeLst = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 27: {
          return v_$x;
        }
        case 28: {
          const v_$pk__28 = v_$k[1];
          switch (v_$x[0]) {
            case 3: {
              v_$k = v_$pk__28;
              continue;
            }
            case 4: {
              v_$x = (() => {
                const v_$inl6$x = v_$k[2];
                return __concat(
                  (s => {
                    switch (s[0]) {
                      case 1: {
                        return "T";
                      }
                      case 2: {
                        return "F";
                      }
                    }
                  })(v_$inl6$x[1]),
                  v_$x[1]
                );
              })();
              v_$k = v_$pk__28;
              continue;
            }
          }
        }
      }
    }
  };

  const v_$cps$describeLst = (v_xs, v_$k) => {
    while (true) {
      switch (v_xs[0]) {
        case 25: {
          return v_$apply$describeLst(v_$k, [4, ""]);
        }
        case 26: {
          const v_h = v_xs[1];
          const v_t = v_xs[2];
          v_$k = [28, v_$k, v_h];
          v_xs = v_t;
          continue;
        }
      }
    }
  };

  const v_$apply$$lift$14 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 29: {
          return v_$x;
        }
        case 30: {
          const v_$pk__30 = v_$k[1];
          const v_____f0 = v_$k[2];
          v_$x = (v_$k[0] = 26, v_$k[1] = [
            796142685,
            v_____f0
          ], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__30;
          continue;
        }
      }
    }
  };

  const v_$cps$$lift$14 = (v_____input, v_$k) => {
    while (true) {
      switch (v_____input[0]) {
        case 25: {
          return v_$apply$$lift$14(v_$k, v_____input);
        }
        case 26: {
          const v_____f0 = v_____input[1];
          const v_____f1 = v_____input[2];
          v_$k = [30, v_$k, v_____f0];
          v_____input = v_____f1;
          continue;
        }
      }
    }
  };

  const v_$inl8$____input = v_defaultJust;
  const v_$inl11$m = (s => {
    switch (s[0]) {
      case 11: {
        return v_$inl8$____input;
      }
      case 12: {
        return [12, [796142685, v_$inl8$____input[1]]];
      }
    }
  })(v_$inl8$____input);
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__6 = s[1];
        return [3, v_$do__e__6];
      }
      case 4: {
        const v_a = s[1];
        {
          const __s = v_$cps$describeLst(
            v_$cps$$lift$14(v_defaultBools, [29]),
            [27]
          );
          switch (__s[0]) {
            case 3: {
              const v_$do__e__5 = __s[1];
              return [3, v_$do__e__5];
            }
            case 4: {
              const v_b = __s[1];
              const v_$inl15$____input = v_defaultRight;
              const v_$inl21$r = (s => {
                switch (s[0]) {
                  case 3: {
                    return v_$inl15$____input;
                  }
                  case 4: {
                    const v_$inl13$____f0 = s[1];
                    return [
                      4,
                      (s => {
                        switch (s[0]) {
                          case 11: {
                            return v_$inl13$____f0;
                          }
                          case 12: {
                            return [12, [796142685, v_$inl13$____f0[1]]];
                          }
                        }
                      })(v_$inl13$____f0)
                    ];
                  }
                }
              })(v_$inl15$____input);
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 3: {
                      return [4, "ErrA"];
                    }
                    case 4: {
                      const v_$inl18$m = v_$inl21$r[1];
                      switch (v_$inl18$m[0]) {
                        case 11: {
                          return [4, "N"];
                        }
                        case 12: {
                          const v_$inl20$x = v_$inl18$m[1];
                          return __concat(
                            "J",
                            (s => {
                              switch (s[0]) {
                                case 1: {
                                  return "T";
                                }
                                case 2: {
                                  return "F";
                                }
                              }
                            })(v_$inl20$x[1])
                          );
                        }
                      }
                    }
                  }
                })(v_$inl21$r);
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__4 = __s[1];
                    return [3, v_$do__e__4];
                  }
                  case 4: {
                    const v_c = __s[1];
                    {
                      const __s = __concat(v_a, " / ");
                      switch (__s[0]) {
                        case 3: {
                          const v_$do__e__3 = __s[1];
                          return [3, v_$do__e__3];
                        }
                        case 4: {
                          const v_s0 = __s[1];
                          {
                            const __s = __concat(v_s0, v_b);
                            switch (__s[0]) {
                              case 3: {
                                const v_$do__e__2 = __s[1];
                                return [3, v_$do__e__2];
                              }
                              case 4: {
                                const v_s1 = __s[1];
                                {
                                  const __s = __concat(v_s1, " / ");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$do__e__1 = __s[1];
                                      return [3, v_$do__e__1];
                                    }
                                    case 4: {
                                      const v_s2 = __s[1];
                                      return __concat(v_s2, v_c);
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
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
        case 11: {
          return [4, "N"];
        }
        case 12: {
          const v_$inl10$x = v_$inl11$m[1];
          return __concat(
            "J",
            (s => {
              switch (s[0]) {
                case 1: {
                  return "T";
                }
                case 2: {
                  return "F";
                }
              }
            })(v_$inl10$x[1])
          );
        }
      }
    })(v_$inl11$m)
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
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
          v_$k = [32, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 33: {
          return v_$x;
        }
        case 34: {
          const v_$pk__34 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__34;
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
          v_$k = [34, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl24$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl24$x[1]];
          }
          case 4: {
            return [5, v_$inl24$x[1]];
          }
        }
      })(v_$inl24$x),
      [33]
    ),
    [31]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
