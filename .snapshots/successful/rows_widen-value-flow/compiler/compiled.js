"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_vStr = [3, "strErr"];

  const v_vSecond = [3, [27]];

  const v_vOkA = [4, 7 | 0];

  const v_vFirst = [3, [26]];

  const v_vErrB = [3, [25]];

  const v_vErrA = [3, [24]];

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

  const v_showTwoA = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 925038822: {
                const v_t = __s[1];
                {
                  const __s = v_t;
                  switch (__s[0]) {
                    case 26: {
                      return "First";
                    }
                    case 27: {
                      return "Second";
                    }
                  }
                }
              }
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showStrA = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 1615808600: {
                const v_s = __s[1];
                return v_s;
              }
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showAB = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
              case 2269767818: {
                const v__b = __s[1];
                return "ErrB";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
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

  const v_pureIO = v_x => [5, v_x];

  const v_printErr = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 19: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
  };

  const v_failIO = v_e => [6, v_e];

  const v_eitherToIO = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return v_failIO(v_e);
        }
        case 4: {
          const v_a = __s[1];
          return v_pureIO(v_a);
        }
      }
    }
  };

  const v_appendTagged = (v_acc, v_label, v_val) => {
    {
      const __s = v_tagged(v_label, v_val);
      switch (__s[0]) {
        case 3: {
          const v__do_e_2 = __s[1];
          return [3, v__do_e_2];
        }
        case 4: {
          const v_line = __s[1];
          return __concat(v_acc, v_line);
        }
      }
    }
  };

  const v__lift_18 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [1615808600, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v_strWiden = v__lift_18(v_vStr);

  const v__lift_17 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2252990199, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__lift_16 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [925038822, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v_nestedUnion = v_m => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 11: {
          return v__lift_16(v_vFirst);
        }
        case 12: {
          const v_b = __s[1];
          {
            const __s = v_b;
            switch (__s[0]) {
              case 1: {
                return v__lift_17(v_vErrA);
              }
              case 2: {
                return v__lift_16(v_vSecond);
              }
            }
          }
        }
      }
    }
  };

  const v__lift_14 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2269767818, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__lift_13 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2252990199, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v_caseUnion = v_flag => {
    {
      const __s = v_flag;
      switch (__s[0]) {
        case 1: {
          return v__lift_13(v_vErrA);
        }
        case 2: {
          return v__lift_14(v_vErrB);
        }
      }
    }
  };

  const v_defBodyLeft = v__lift_13(v_vErrA);

  const v_defBodyRight = v__lift_13(v_vOkA);

  const v__let_15 = v_x => v__lift_14(v_x);

  const v_letBody = v__let_15(v_vErrB);

  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_10 = s[1];
        return [3, v__do_e_10];
      }
      case 4: {
        const v_r01 = s[1];
        return (s => {
          switch (s[0]) {
            case 3: {
              const v__do_e_9 = s[1];
              return [3, v__do_e_9];
            }
            case 4: {
              const v_r02 = s[1];
              return (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_8 = s[1];
                    return [3, v__do_e_8];
                  }
                  case 4: {
                    const v_r03 = s[1];
                    return (s => {
                      switch (s[0]) {
                        case 3: {
                          const v__do_e_7 = s[1];
                          return [3, v__do_e_7];
                        }
                        case 4: {
                          const v_r04 = s[1];
                          return (s => {
                            switch (s[0]) {
                              case 3: {
                                const v__do_e_6 = s[1];
                                return [3, v__do_e_6];
                              }
                              case 4: {
                                const v_r05 = s[1];
                                return (s => {
                                  switch (s[0]) {
                                    case 3: {
                                      const v__do_e_5 = s[1];
                                      return [3, v__do_e_5];
                                    }
                                    case 4: {
                                      const v_r06 = s[1];
                                      return (s => {
                                        switch (s[0]) {
                                          case 3: {
                                            const v__do_e_4 = s[1];
                                            return [3, v__do_e_4];
                                          }
                                          case 4: {
                                            const v_r07 = s[1];
                                            return (s => {
                                              switch (s[0]) {
                                                case 3: {
                                                  const v__do_e_3 = s[1];
                                                  return [3, v__do_e_3];
                                                }
                                                case 4: {
                                                  const v_r08 = s[1];
                                                  return v_appendTagged(
                                                    v_r08,
                                                    "strWiden",
                                                    v_showStrA(v_strWiden)
                                                  );
                                                }
                                              }
                                            })(
                                              v_appendTagged(
                                                v_r07,
                                                "nestedJustFalse",
                                                v_showTwoA(
                                                  v_nestedUnion([12, [2]])
                                                )
                                              )
                                            );
                                          }
                                        }
                                      })(
                                        v_appendTagged(
                                          v_r06,
                                          "nestedJustTrue",
                                          v_showTwoA(v_nestedUnion([12, [1]]))
                                        )
                                      );
                                    }
                                  }
                                })(
                                  v_appendTagged(
                                    v_r05,
                                    "nestedNothing",
                                    v_showTwoA(v_nestedUnion([11]))
                                  )
                                );
                              }
                            }
                          })(
                            v_appendTagged(
                              v_r04,
                              "caseFalse",
                              v_showAB(v_caseUnion([2]))
                            )
                          );
                        }
                      }
                    })(
                      v_appendTagged(
                        v_r03,
                        "caseTrue",
                        v_showAB(v_caseUnion([1]))
                      )
                    );
                  }
                }
              })(v_appendTagged(v_r02, "letBody", v_showAB(v_letBody)));
            }
          }
        })(v_appendTagged(v_r01, "defBodyRight", v_showAB(v_defBodyRight)));
      }
    }
  })(v_tagged("defBodyLeft", v_showAB(v_defBodyLeft)));

  const v__bi_IO_Stdout_print = v__x0 => [7, v__x0, [5, [0]]];

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 28: {
            return v__x;
          }
          case 29: {
            const v__pk_29 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_29;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, v_printErr(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 29, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = v_io => v__cps__df_handleErrorIO_0(v_io, [28]);

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 30: {
            return v__x;
          }
          case 31: {
            const v__pk_31 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_31;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_4(v__k, v__bi_IO_Stdout_print(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_4(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 31, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_4 = v_io => v__cps__df_andThenIO_4(v_io, [30]);

  const main = v__df_handleErrorIO_0(v__df_andThenIO_4(v_eitherToIO(v_render)));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
