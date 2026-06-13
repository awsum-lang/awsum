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
          const v__do_e_1 = __s[1];
          return [3, v__do_e_1];
        }
        case 4: {
          const v_a = __s[1];
          {
            const __s = __concat(v_a, v_val);
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                return [3, v__do_e_0];
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
          const v__inl0_eff = __print(v_io[1]);
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
        const v__inl6___f0 = s[1];
        return [
          25,
          (s => {
            switch (s[0]) {
              case 11: {
                return v__inl6___f0;
              }
              case 12: {
                const v__inl7___f0 = s[1];
                return [
                  12,
                  (s => {
                    switch (s[0]) {
                      case 3: {
                        return v__inl7___f0;
                      }
                      case 4: {
                        return [4, [796142685, v__inl7___f0[1]]];
                      }
                    }
                  })(v__inl7___f0)
                ];
              }
            }
          })(v__inl6___f0)
        ];
      }
    }
  })(v_narrowDeep);

  const v_directDeepU = [25, [12, [4, [1759602215, [0]]]]];

  const v_directDeepT = [25, [12, [4, [796142685, [1]]]]];

  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_4 = s[1];
        return [3, v__do_e_4];
      }
      case 4: {
        const v_r01 = s[1];
        let v__inl33_scrut;
        $join32: {
          const __s = v_tagged(
            "directDeepU",
            (s => {
              switch (s[0]) {
                case 25: {
                  const v__inl16_m = s[1];
                  switch (v__inl16_m[0]) {
                    case 11: {
                      return "N";
                    }
                    case 12: {
                      {
                        const __s = v__inl16_m[1];
                        switch (__s[0]) {
                          case 3: {
                            return "L";
                          }
                          case 4: {
                            const v__inl19_bu = __s[1];
                            switch (v__inl19_bu[0]) {
                              case 796142685: {
                                {
                                  const __s = v__inl19_bu[1];
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
              const v__inl22__do_e_2 = __s[1];
              return [3, v__inl22__do_e_2];
            }
            case 4: {
              const v__inl23_line = __s[1];
              v__inl33_scrut = __concat(v_r01, v__inl23_line);
              break $join32;
            }
          }
        }
        switch (v__inl33_scrut[0]) {
          case 3: {
            return v__inl33_scrut;
          }
          case 4: {
            {
              const __s = v_tagged(
                "widenedDeep",
                (s => {
                  switch (s[0]) {
                    case 25: {
                      const v__inl24_m = s[1];
                      switch (v__inl24_m[0]) {
                        case 11: {
                          return "N";
                        }
                        case 12: {
                          {
                            const __s = v__inl24_m[1];
                            switch (__s[0]) {
                              case 3: {
                                return "L";
                              }
                              case 4: {
                                const v__inl27_bu = __s[1];
                                switch (v__inl27_bu[0]) {
                                  case 796142685: {
                                    {
                                      const __s = v__inl27_bu[1];
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
                  const v__inl30__do_e_2 = __s[1];
                  return [3, v__inl30__do_e_2];
                }
                case 4: {
                  const v__inl31_line = __s[1];
                  return __concat(v__inl33_scrut[1], v__inl31_line);
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
            const v__inl10_m = s[1];
            switch (v__inl10_m[0]) {
              case 11: {
                return "N";
              }
              case 12: {
                {
                  const __s = v__inl10_m[1];
                  switch (__s[0]) {
                    case 3: {
                      return "L";
                    }
                    case 4: {
                      const v__inl13_bu = __s[1];
                      switch (v__inl13_bu[0]) {
                        case 796142685: {
                          {
                            const __s = v__inl13_bu[1];
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
      (v__inl36_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl36_x[1]];
            }
            case 4: {
              return [5, v__inl36_x[1]];
            }
          }
        })(v__inl36_x))(v_render),
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
