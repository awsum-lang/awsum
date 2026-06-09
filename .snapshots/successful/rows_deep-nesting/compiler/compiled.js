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

  const v_showDeep = v_b => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 25: {
          const v_m = __s[1];
          {
            const __s = v_m;
            switch (__s[0]) {
              case 11: {
                return "N";
              }
              case 12: {
                const v_inner = __s[1];
                {
                  const __s = v_inner;
                  switch (__s[0]) {
                    case 3: {
                      const v__e = __s[1];
                      return "L";
                    }
                    case 4: {
                      const v_bu = __s[1];
                      {
                        const __s = v_bu;
                        switch (__s[0]) {
                          case 796142685: {
                            const v_x = __s[1];
                            {
                              const __s = v_x;
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
                            const v_u = __s[1];
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

  const v_narrowDeep = [25, [12, [4, [1]]]];

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

  const v_directDeepU = [25, [12, [4, [1759602215, [0]]]]];

  const v_directDeepT = [25, [12, [4, [796142685, [1]]]]];

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

  const v__lift_15 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, v___f0];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, [796142685, v___f0]];
        }
      }
    }
  };

  const v__lift_14 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 11: {
          return [11];
        }
        case 12: {
          const v___f0 = __s[1];
          return [12, v__lift_15(v___f0)];
        }
      }
    }
  };

  const v__lift_13 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 25: {
          const v___f0 = __s[1];
          return [25, v__lift_14(v___f0)];
        }
      }
    }
  };

  const v_widenedDeep = v__lift_13(v_narrowDeep);

  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_4 = s[1];
        return [3, v__do_e_4];
      }
      case 4: {
        const v_r01 = s[1];
        return (s => {
          switch (s[0]) {
            case 3: {
              const v__do_e_3 = s[1];
              return [3, v__do_e_3];
            }
            case 4: {
              const v_r02 = s[1];
              return v_appendTagged(
                v_r02,
                "widenedDeep",
                v_showDeep(v_widenedDeep)
              );
            }
          }
        })(v_appendTagged(v_r01, "directDeepU", v_showDeep(v_directDeepU)));
      }
    }
  })(v_tagged("directDeepT", v_showDeep(v_directDeepT)));

  const v__bi_IO_Stdout_print = v__x0 => [7, v__x0, [5, [0]]];

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 26: {
            return v__x;
          }
          case 27: {
            const v__pk_27 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_27;
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
            const __t1 = (v_io[0] = 27, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = v_io => v__cps__df_handleErrorIO_0(v_io, [26]);

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
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
            const __t1 = (v_io[0] = 29, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_4 = v_io => v__cps__df_andThenIO_4(v_io, [28]);

  const main = v__df_handleErrorIO_0(v__df_andThenIO_4(v_eitherToIO(v_render)));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
