"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_tagged = (v_label, v_val) => {
    {
      const __s = __concat(v_label, "=");
      switch (__s[0]) {
        case 3: {
          const v_$do__e__1 = __s[1];
          return [3, v_$do__e__1];
        }
        case 4: {
          const v_a = __s[1];
          {
            const __s = __concat(v_a, v_val);
            switch (__s[0]) {
              case 3: {
                const v_$do__e__0 = __s[1];
                return [3, v_$do__e__0];
              }
              case 4: {
                const v_b = __s[1];
                return __concat(v_b, "\n");
              }
            }
          }
        }
      }
    }
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

  const v_narrowDeep = [25, [12, [4, [1]]]];

  const v_widenedDeep = (s => {
    switch (s[0]) {
      case 25: {
        const v_$inl6$____f0 = s[1];
        return [
          25,
          (s => {
            switch (s[0]) {
              case 11: {
                return v_$inl6$____f0;
              }
              case 12: {
                const v_$inl7$____f0 = s[1];
                return [
                  12,
                  (s => {
                    switch (s[0]) {
                      case 3: {
                        return v_$inl7$____f0;
                      }
                      case 4: {
                        return [4, [796142685, v_$inl7$____f0[1]]];
                      }
                    }
                  })(v_$inl7$____f0)
                ];
              }
            }
          })(v_$inl6$____f0)
        ];
      }
    }
  })(v_narrowDeep);

  const v_directDeepU = [25, [12, [4, [1759602215, [0]]]]];

  const v_directDeepT = [25, [12, [4, [796142685, [1]]]]];

  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__4 = s[1];
        return [3, v_$do__e__4];
      }
      case 4: {
        const v_r01 = s[1];
        let v_$inl33$scrut;
        $join32: {
          const __s = v_tagged(
            "directDeepU",
            (s => {
              switch (s[0]) {
                case 25: {
                  const v_$inl16$m = s[1];
                  switch (v_$inl16$m[0]) {
                    case 11: {
                      return "N";
                    }
                    case 12: {
                      {
                        const __s = v_$inl16$m[1];
                        switch (__s[0]) {
                          case 3: {
                            return "L";
                          }
                          case 4: {
                            const v_$inl19$bu = __s[1];
                            switch (v_$inl19$bu[0]) {
                              case 796142685: {
                                {
                                  const __s = v_$inl19$bu[1];
                                  switch (__s[0]) {
                                    case 1: {
                                      return "RT";
                                    }
                                    case 2: {
                                      return "RF";
                                    }
                                  }
                                }
                              }
                              case 1759602215: {
                                return "RU";
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            })(v_directDeepU)
          );
          switch (__s[0]) {
            case 3: {
              const v_$inl22$$do__e__2 = __s[1];
              return [3, v_$inl22$$do__e__2];
            }
            case 4: {
              const v_$inl23$line = __s[1];
              v_$inl33$scrut = __concat(v_r01, v_$inl23$line);
              break $join32;
            }
          }
        }
        switch (v_$inl33$scrut[0]) {
          case 3: {
            return v_$inl33$scrut;
          }
          case 4: {
            {
              const __s = v_tagged(
                "widenedDeep",
                (s => {
                  switch (s[0]) {
                    case 25: {
                      const v_$inl24$m = s[1];
                      switch (v_$inl24$m[0]) {
                        case 11: {
                          return "N";
                        }
                        case 12: {
                          {
                            const __s = v_$inl24$m[1];
                            switch (__s[0]) {
                              case 3: {
                                return "L";
                              }
                              case 4: {
                                const v_$inl27$bu = __s[1];
                                switch (v_$inl27$bu[0]) {
                                  case 796142685: {
                                    {
                                      const __s = v_$inl27$bu[1];
                                      switch (__s[0]) {
                                        case 1: {
                                          return "RT";
                                        }
                                        case 2: {
                                          return "RF";
                                        }
                                      }
                                    }
                                  }
                                  case 1759602215: {
                                    return "RU";
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                })(v_widenedDeep)
              );
              switch (__s[0]) {
                case 3: {
                  const v_$inl30$$do__e__2 = __s[1];
                  return [3, v_$inl30$$do__e__2];
                }
                case 4: {
                  const v_$inl31$line = __s[1];
                  return __concat(v_$inl33$scrut[1], v_$inl31$line);
                }
              }
            }
          }
        }
      }
    }
  })(
    v_tagged(
      "directDeepT",
      (s => {
        switch (s[0]) {
          case 25: {
            const v_$inl10$m = s[1];
            switch (v_$inl10$m[0]) {
              case 11: {
                return "N";
              }
              case 12: {
                {
                  const __s = v_$inl10$m[1];
                  switch (__s[0]) {
                    case 3: {
                      return "L";
                    }
                    case 4: {
                      const v_$inl13$bu = __s[1];
                      switch (v_$inl13$bu[0]) {
                        case 796142685: {
                          {
                            const __s = v_$inl13$bu[1];
                            switch (__s[0]) {
                              case 1: {
                                return "RT";
                              }
                              case 2: {
                                return "RF";
                              }
                            }
                          }
                        }
                        case 1759602215: {
                          return "RU";
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      })(v_directDeepT)
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

  const v_$inl36$x = v_render;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl36$x[1]];
          }
          case 4: {
            return [5, v_$inl36$x[1]];
          }
        }
      })(v_$inl36$x),
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
