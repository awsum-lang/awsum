"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const v_toRowB = (v__s) => {
    return [2269767818, [28]];
  };

  const v_toRowA = (v__s) => {
    return [2252990199, [27]];
  };

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

  const v_showABC = (v_e) => {
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

  const v_showAB = (v_e) => {
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

  const v_rightSrc = [4, 5 | 0];

  const v_remap = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3640903312: {
          const v__y = __s[1];
          return [2269767818, [28]];
        }
        case 3657680931: {
          const v__x = __s[1];
          return [2252990199, [27]];
        }
      }
    }
  };

  const v_pureIO = (v_x) => {
    return [5, v_x];
  };

  const v_printErr = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 19: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
  };

  const v_leftY = [3, [3640903312, [26]]];

  const v_leftX = [3, [3657680931, [25]]];

  const v_leftSrc = [3, [24]];

  const v_failIO = (v_e) => {
    return [6, v_e];
  };

  const v_eitherToIO = (v_x) => {
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

  const v__df_mapLeft_2 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_remap(v_e)];
        }
        case 4: {
          const v_a = __s[1];
          return [4, v_a];
        }
      }
    }
  };

  const v_remappedX = v__df_mapLeft_2(v_leftX);

  const v_remappedY = v__df_mapLeft_2(v_leftY);

  const v__df_mapLeft_1 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_toRowB(v_e)];
        }
        case 4: {
          const v_a = __s[1];
          return [4, v_a];
        }
      }
    }
  };

  const v_mappedB = v__df_mapLeft_1(v_leftSrc);

  const v__df_mapLeft_0 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_toRowA(v_e)];
        }
        case 4: {
          const v_a = __s[1];
          return [4, v_a];
        }
      }
    }
  };

  const v_mappedA = v__df_mapLeft_0(v_leftSrc);

  const v_mappedOk = v__df_mapLeft_0(v_rightSrc);

  const v_render = ((s) => {
    switch (s[0]) {
      case 3: {
        const v__do_e_6 = s[1];
        return [3, v__do_e_6];
      }
      case 4: {
        const v_r01 = s[1];
        return ((s) => {
          switch (s[0]) {
            case 3: {
              const v__do_e_5 = s[1];
              return [3, v__do_e_5];
            }
            case 4: {
              const v_r02 = s[1];
              return ((s) => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_4 = s[1];
                    return [3, v__do_e_4];
                  }
                  case 4: {
                    const v_r03 = s[1];
                    return ((s) => {
                      switch (s[0]) {
                        case 3: {
                          const v__do_e_3 = s[1];
                          return [3, v__do_e_3];
                        }
                        case 4: {
                          const v_r04 = s[1];
                          return v_appendTagged(
                            v_r04,
                            "remappedY",
                            v_showABC(v_remappedY)
                          );
                        }
                      }
                    })(
                      v_appendTagged(v_r03, "remappedX", v_showABC(v_remappedX))
                    );
                  }
                }
              })(v_appendTagged(v_r02, "mappedOk", v_showAB(v_mappedOk)));
            }
          }
        })(v_appendTagged(v_r01, "mappedB", v_showAB(v_mappedB)));
      }
    }
  })(v_tagged("mappedA", v_showAB(v_mappedA)));

  const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
  };

  const v__apply__df_handleErrorIO_3 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 29: {
            return v__x;
          }
          case 30: {
            const v__pk_30 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_30;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_3 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_3(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_3(v__k, v_printErr(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 30, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_3 = (v_io) => {
    return v__cps__df_handleErrorIO_3(v_io, [29]);
  };

  const v__apply__df_andThenIO_7 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 31: {
            return v__x;
          }
          case 32: {
            const v__pk_32 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_32;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_7 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_7(v__k, v__bi_IO_Stdout_print(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_7(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 32, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_7 = (v_io) => {
    return v__cps__df_andThenIO_7(v_io, [31]);
  };

  const main = v__df_handleErrorIO_3(v__df_andThenIO_7(v_eitherToIO(v_render)));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
