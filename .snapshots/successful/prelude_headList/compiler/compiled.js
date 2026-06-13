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

  const main = (v__inl91_noElems =>
    (v__inl67_single =>
      (v__inl71_multi =>
        (() => {
          let v__inl73_scrut;
          $join72: {
            const __s = (s => {
              switch (s[0]) {
                case 11: {
                  return [4, "Nothing"];
                }
                case 12: {
                  return __concat("Just ", v__inl91_noElems[1]);
                }
              }
            })(v__inl91_noElems);
            switch (__s[0]) {
              case 3: {
                return [7, "STRING_TOO_LONG", [5, [0]]];
              }
              case 4: {
                const v__inl78_a = __s[1];
                v__inl73_scrut = (s => {
                  switch (s[0]) {
                    case 3: {
                      const v__inl80__do_e_4 = s[1];
                      return [3, v__inl80__do_e_4];
                    }
                    case 4: {
                      const v__inl81_b = s[1];
                      {
                        const __s = (s => {
                          switch (s[0]) {
                            case 11: {
                              return [4, "Nothing"];
                            }
                            case 12: {
                              return __concat("Just ", v__inl71_multi[1]);
                            }
                          }
                        })(v__inl71_multi);
                        switch (__s[0]) {
                          case 3: {
                            const v__inl83__do_e_3 = __s[1];
                            return [3, v__inl83__do_e_3];
                          }
                          case 4: {
                            const v__inl84_c = __s[1];
                            {
                              const __s = __concat(v__inl78_a, "|");
                              switch (__s[0]) {
                                case 3: {
                                  const v__inl85__do_e_2 = __s[1];
                                  return [3, v__inl85__do_e_2];
                                }
                                case 4: {
                                  const v__inl86_s0 = __s[1];
                                  {
                                    const __s = __concat(
                                      v__inl86_s0,
                                      v__inl81_b
                                    );
                                    switch (__s[0]) {
                                      case 3: {
                                        const v__inl87__do_e_1 = __s[1];
                                        return [3, v__inl87__do_e_1];
                                      }
                                      case 4: {
                                        const v__inl88_s1 = __s[1];
                                        {
                                          const __s = __concat(
                                            v__inl88_s1,
                                            "|"
                                          );
                                          switch (__s[0]) {
                                            case 3: {
                                              const v__inl89__do_e_0 = __s[1];
                                              return [3, v__inl89__do_e_0];
                                            }
                                            case 4: {
                                              const v__inl90_s2 = __s[1];
                                              return __concat(
                                                v__inl90_s2,
                                                v__inl84_c
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
                      case 11: {
                        return [4, "Nothing"];
                      }
                      case 12: {
                        return __concat("Just ", v__inl67_single[1]);
                      }
                    }
                  })(v__inl67_single)
                );
                break $join72;
              }
            }
          }
          switch (v__inl73_scrut[0]) {
            case 3: {
              return [7, "STRING_TOO_LONG", [5, [0]]];
            }
            case 4: {
              return [7, v__inl73_scrut[1], [5, [0]]];
            }
          }
        })())(
        (v__inl68_xs =>
          (s => {
            switch (s[0]) {
              case 13: {
                return [11];
              }
              case 14: {
                return [12, v__inl68_xs[1]];
              }
            }
          })(v__inl68_xs))([14, "a", [14, "b", [14, "c", [13]]]])
      ))(
      (v__inl64_xs =>
        (s => {
          switch (s[0]) {
            case 13: {
              return [11];
            }
            case 14: {
              return [12, v__inl64_xs[1]];
            }
          }
        })(v__inl64_xs))([14, "a", [13]])
    ))(
    (v__inl63_xs =>
      (s => {
        switch (s[0]) {
          case 13: {
            return [11];
          }
          case 14: {
            return [12, v__inl63_xs[1]];
          }
        }
      })(v__inl63_xs))([13])
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
