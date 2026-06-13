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

  const main = (v__inl97_fromNothing =>
    (v__inl70_fromJust =>
      (v__inl74_chained =>
        (() => {
          let v__inl76_scrut;
          $join75: {
            const __s = (s => {
              switch (s[0]) {
                case 3: {
                  return [4, "Left Missing"];
                }
                case 4: {
                  return __concat("Right ", v__inl97_fromNothing[1]);
                }
              }
            })(v__inl97_fromNothing);
            switch (__s[0]) {
              case 3: {
                return [7, "STRING_TOO_LONG", [5, [0]]];
              }
              case 4: {
                const v__inl82_a = __s[1];
                v__inl76_scrut = (s => {
                  switch (s[0]) {
                    case 3: {
                      const v__inl85__do_e_5 = s[1];
                      return [3, v__inl85__do_e_5];
                    }
                    case 4: {
                      const v__inl86_b = s[1];
                      {
                        const __s = (s => {
                          switch (s[0]) {
                            case 3: {
                              return [4, "Left Missing"];
                            }
                            case 4: {
                              return __concat("Right ", v__inl74_chained[1]);
                            }
                          }
                        })(v__inl74_chained);
                        switch (__s[0]) {
                          case 3: {
                            const v__inl89__do_e_4 = __s[1];
                            return [3, v__inl89__do_e_4];
                          }
                          case 4: {
                            const v__inl90_c = __s[1];
                            {
                              const __s = __concat(v__inl82_a, "|");
                              switch (__s[0]) {
                                case 3: {
                                  const v__inl91__do_e_3 = __s[1];
                                  return [3, v__inl91__do_e_3];
                                }
                                case 4: {
                                  const v__inl92_sep = __s[1];
                                  {
                                    const __s = __concat(
                                      v__inl92_sep,
                                      v__inl86_b
                                    );
                                    switch (__s[0]) {
                                      case 3: {
                                        const v__inl93__do_e_2 = __s[1];
                                        return [3, v__inl93__do_e_2];
                                      }
                                      case 4: {
                                        const v__inl94_s1 = __s[1];
                                        {
                                          const __s = __concat(
                                            v__inl94_s1,
                                            "|"
                                          );
                                          switch (__s[0]) {
                                            case 3: {
                                              const v__inl95__do_e_1 = __s[1];
                                              return [3, v__inl95__do_e_1];
                                            }
                                            case 4: {
                                              const v__inl96_s2 = __s[1];
                                              return __concat(
                                                v__inl96_s2,
                                                v__inl90_c
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
                })(
                  (s => {
                    switch (s[0]) {
                      case 3: {
                        return [4, "Left Missing"];
                      }
                      case 4: {
                        return __concat("Right ", v__inl70_fromJust[1]);
                      }
                    }
                  })(v__inl70_fromJust)
                );
                break $join75;
              }
            }
          }
          switch (v__inl76_scrut[0]) {
            case 3: {
              return [7, "STRING_TOO_LONG", [5, [0]]];
            }
            case 4: {
              return [7, v__inl76_scrut[1], [5, [0]]];
            }
          }
        })())(
        (v__inl71_xs =>
          (s => {
            switch (s[0]) {
              case 13: {
                return [3, [24]];
              }
              case 14: {
                return [4, v__inl71_xs[1]];
              }
            }
          })(v__inl71_xs))([14, "first", [14, "second", [13]]])
      ))([4, "hi"]))([3, [24]]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
