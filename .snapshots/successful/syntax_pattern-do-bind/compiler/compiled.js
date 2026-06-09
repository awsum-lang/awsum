"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const __entryArgEither = (arg) => {
    if (arg.length > 134217728) {
      return [3, [589989748, [19]]];
    }
    for (let i = 0; i < arg.length; i++) {
      const c = arg.charCodeAt(i);
      if (c >= 0xD800 && c <= 0xDBFF) {
        if (i + 1 >= arg.length) {
          return [3, [502975519, [20]]];
        }
        const next = arg.charCodeAt(i + 1);
        if (next < 0xDC00 || next > 0xDFFF) {
          return [3, [502975519, [20]]];
        }
        i++;
      } else {
        if (c >= 0xDC00 && c <= 0xDFFF) {
          return [3, [502975519, [20]]];
        }
      }
    }
    return [4, arg];
  };

  const __getArgs = () => {
    const args = process.argv.slice(2);
    let list = [13];
    for (let i = args.length - 1; i >= 0; i--) {
      const v = __entryArgEither(args[i]);
      if (v[0] !== 4) {
        return v;
      }
      list = [14, v[1], list];
    }
    return [4, list];
  };

  const v_pureEither = (v_x) => {
    return [4, v_x];
  };

  const v_opTuple = (v__wild0) => {
    return [4, [16, 1 | 0, 2 | 0, 3 | 0]];
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

  const v_handleInputErr = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 502975519: {
          const v__u = __s[1];
          return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
        }
        case 589989748: {
          const v__l = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
  };

  const v__let_13 = (v_res) => {
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "PARSE_ERROR", [5, [0]]];
        }
        case 4: {
          const v_n = __s[1];
          return [7, String(v_n), [5, [0]]];
        }
      }
    }
  };

  const v_processInput = (v_raw) => {
    return v__let_13(
      ((s) => {
        switch (s[0]) {
          case 3: {
            const v__do_e_0 = s[1];
            return [3, v__do_e_0];
          }
          case 4: {
            const v___p0 = s[1];
            return ((s) => {
              switch (s[0]) {
                case 16: {
                  const v_a = s[1];
                  const v_b = s[2];
                  const v_c = s[3];
                  return v_pureEither(
                    ((s) => {
                      switch (s[0]) {
                        case 3: {
                          const v___w0 = s[1];
                          return v_c;
                        }
                        case 4: {
                          const v_ab = s[1];
                          return ((s) => {
                            switch (s[0]) {
                              case 3: {
                                const v___w0 = s[1];
                                return v_c;
                              }
                              case 4: {
                                const v_abc = s[1];
                                return v_abc;
                              }
                            }
                          })(__addInt32(v_ab, v_c));
                        }
                      }
                    })(__addInt32(v_a, v_b))
                  );
                }
              }
            })(v___p0);
          }
        }
      })(v_opTuple(v_raw))
    );
  };

  const v_processArgs = (v_args) => {
    {
      const __s = v_headList(v_args);
      switch (__s[0]) {
        case 11: {
          return [7, "NO_ARG", [5, [0]]];
        }
        case 12: {
          const v_first = __s[1];
          return v_processInput(v_first);
        }
      }
    }
  };

  const v__io_getargs_cont = (v_result) => {
    {
      const __s = v_result;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [6, v_e];
        }
        case 4: {
          const v_s = __s[1];
          return [5, v_s];
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 23: {
            return v__x;
          }
          case 24: {
            const v__pk_24 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_24;
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
            return v__apply__df_handleErrorIO_0(v__k, v_handleInputErr(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 24, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [8, [18, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = (v_io) => {
    return v__cps__df_handleErrorIO_0(v_io, [23]);
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 25: {
            return v__x;
          }
          case 26: {
            const v__pk_26 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_26;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(
              v__k,
              v_processArgs(v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 26, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [8, [17, v_cont]]);
          }
        }
      }
    }
  };

  const v__df__rowmono_0_andThenIO_4 = (v_io) => {
    return v__cps__df__rowmono_0_andThenIO_4(v_io, [25]);
  };

  const v__apply__scc__apply1__df__lam_14_5__df__lam_9_1 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 27: {
            return v__x;
          }
          case 28: {
            const v__pk_28 = __s[1];
            const __t0 = v__pk_28;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 29: {
            const v__pk_29 = __s[1];
            const __t0 = v__pk_29;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_14_5__df__lam_9_1 = (v__args, v__k) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 20: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 17: {
                  const v__cap17_0 = __s[1];
                  const __t0 = (v__args[0] = 21, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 18: {
                  const v__cap18_0 = __s[1];
                  const __t0 = (v__args[0] = 22, v__args[1] = v__cap18_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 19: {
                  return v__apply__scc__apply1__df__lam_14_5__df__lam_9_1(
                    v__k,
                    v__io_getargs_cont(v__arg0)
                  );
                }
              }
            }
          }
          case 21: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 20, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [28, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 22: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 20, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [29, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_14_5__df__lam_9_1 = (v__args) => {
    return v__cps__scc__apply1__df__lam_14_5__df__lam_9_1(v__args, [27]);
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_14_5__df__lam_9_1([20, v__cl, v__arg0]);
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
          case 8: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __getArgs());
            v_io = __t0;
            continue;
          }
        }
      }
    }
  };

  const main = v__df_handleErrorIO_0(v__df__rowmono_0_andThenIO_4([8, [19]]));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
