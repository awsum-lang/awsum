"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const v_show = (v_m) => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 11: {
          return [4, "Nothing"];
        }
        case 12: {
          const v_s = __s[1];
          return __concat("Just ", v_s);
        }
      }
    }
  };

  const v_runIO = (v_io) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            {
              const __s = __print(v_s);
              switch (__s[0]) {
                case 0: {
                  const __t0 = v_next;
                  v_io = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_headList = (v_xs) => {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 13: {
          return [11];
        }
        case 14: {
          const v_h = __s[1];
          const v__t = __s[2];
          return [12, v_h];
        }
      }
    }
  };

  const v__let_18 = (v_msg) => {
    {
      const __s = v_msg;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
  };

  const v__let_19 = (v_noElems, v_single, v_multi) => {
    return v__let_18(
      ((s) => {
        switch (s[0]) {
          case 3: {
            const v__do_e_5 = s[1];
            return [3, v__do_e_5];
          }
          case 4: {
            const v_a = s[1];
            return ((s) => {
              switch (s[0]) {
                case 3: {
                  const v__do_e_4 = s[1];
                  return [3, v__do_e_4];
                }
                case 4: {
                  const v_b = s[1];
                  return ((s) => {
                    switch (s[0]) {
                      case 3: {
                        const v__do_e_3 = s[1];
                        return [3, v__do_e_3];
                      }
                      case 4: {
                        const v_c = s[1];
                        return ((s) => {
                          switch (s[0]) {
                            case 3: {
                              const v__do_e_2 = s[1];
                              return [3, v__do_e_2];
                            }
                            case 4: {
                              const v_s0 = s[1];
                              return ((s) => {
                                switch (s[0]) {
                                  case 3: {
                                    const v__do_e_1 = s[1];
                                    return [3, v__do_e_1];
                                  }
                                  case 4: {
                                    const v_s1 = s[1];
                                    return ((s) => {
                                      switch (s[0]) {
                                        case 3: {
                                          const v__do_e_0 = s[1];
                                          return [3, v__do_e_0];
                                        }
                                        case 4: {
                                          const v_s2 = s[1];
                                          return __concat(v_s2, v_c);
                                        }
                                      }
                                    })(__concat(v_s1, "|"));
                                  }
                                }
                              })(__concat(v_s0, v_b));
                            }
                          }
                        })(__concat(v_a, "|"));
                      }
                    }
                  })(v_show(v_multi));
                }
              }
            })(v_show(v_single));
          }
        }
      })(v_show(v_noElems))
    );
  };

  const v__let_20 = (v_noElems, v_single) => {
    return v__let_19(
      v_noElems,
      v_single,
      v_headList([14, "a", [14, "b", [14, "c", [13]]]])
    );
  };

  const v__let_21 = (v_noElems) => {
    return v__let_20(v_noElems, v_headList([14, "a", [13]]));
  };

  const main = v__let_21(v_headList([13]));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
