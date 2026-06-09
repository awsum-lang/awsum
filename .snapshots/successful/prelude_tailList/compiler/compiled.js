"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_tailList = v_xs => {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 13: {
          return [11];
        }
        case 14: {
          const v__h = __s[1];
          const v_t = __s[2];
          return [12, v_t];
        }
      }
    }
  };

  const v_runIO = v_io => {
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

  const v__let_13 = v_msg => {
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

  const v__apply_showList = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 15: {
            return v__x;
          }
          case 16: {
            const v__pk_16 = __s[1];
            const v_h = __s[2];
            {
              const __s = v__x;
              switch (__s[0]) {
                case 3: {
                  const v__do_e_1 = __s[1];
                  const __t0 = v__pk_16;
                  const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_1, v__x);
                  v__k = __t0;
                  v__x = __t1;
                  continue;
                }
                case 4: {
                  const v_rest = __s[1];
                  {
                    const __s = __concat(v_h, ",");
                    switch (__s[0]) {
                      case 3: {
                        const v__do_e_0 = __s[1];
                        const __t0 = v__pk_16;
                        const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_0, v__x);
                        v__k = __t0;
                        v__x = __t1;
                        continue;
                      }
                      case 4: {
                        const v_hc = __s[1];
                        const __t0 = v__pk_16;
                        const __t1 = __concat(v_hc, v_rest);
                        v__k = __t0;
                        v__x = __t1;
                        continue;
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

  const v__cps_showList = (v_xs, v__k) => {
    while (true) {
      {
        const __s = v_xs;
        switch (__s[0]) {
          case 13: {
            return v__apply_showList(v__k, [4, "Nil"]);
          }
          case 14: {
            const v_h = __s[1];
            const v_t = __s[2];
            const __t0 = v_t;
            const __t1 = (v_xs[0] = 16, v_xs[1] = v__k, v_xs[2] = v_h, v_xs);
            v_xs = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v_showList = v_xs => v__cps_showList(v_xs, [15]);

  const v_show = v_m => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 11: {
          return [4, "Nothing"];
        }
        case 12: {
          const v_xs = __s[1];
          {
            const __s = v_showList(v_xs);
            switch (__s[0]) {
              case 3: {
                const v__do_e_2 = __s[1];
                return [3, v__do_e_2];
              }
              case 4: {
                const v_rendered = __s[1];
                return __concat("Just ", v_rendered);
              }
            }
          }
        }
      }
    }
  };

  const v__let_14 = (v_noElems, v_single, v_multi) =>
    v__let_13(
      (s => {
        switch (s[0]) {
          case 3: {
            const v__do_e_8 = s[1];
            return [3, v__do_e_8];
          }
          case 4: {
            const v_a = s[1];
            return (s => {
              switch (s[0]) {
                case 3: {
                  const v__do_e_7 = s[1];
                  return [3, v__do_e_7];
                }
                case 4: {
                  const v_b = s[1];
                  return (s => {
                    switch (s[0]) {
                      case 3: {
                        const v__do_e_6 = s[1];
                        return [3, v__do_e_6];
                      }
                      case 4: {
                        const v_c = s[1];
                        return (s => {
                          switch (s[0]) {
                            case 3: {
                              const v__do_e_5 = s[1];
                              return [3, v__do_e_5];
                            }
                            case 4: {
                              const v_s0 = s[1];
                              return (s => {
                                switch (s[0]) {
                                  case 3: {
                                    const v__do_e_4 = s[1];
                                    return [3, v__do_e_4];
                                  }
                                  case 4: {
                                    const v_s1 = s[1];
                                    return (s => {
                                      switch (s[0]) {
                                        case 3: {
                                          const v__do_e_3 = s[1];
                                          return [3, v__do_e_3];
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

  const v__let_15 = (v_noElems, v_single) =>
    v__let_14(
      v_noElems,
      v_single,
      v_tailList([14, "a", [14, "b", [14, "c", [13]]]])
    );

  const v__let_16 = v_noElems =>
    v__let_15(v_noElems, v_tailList([14, "a", [13]]));

  const main = v__let_16(v_tailList([13]));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
