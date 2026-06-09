"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __entryArgEither = arg => {
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

  const v_showN = v_n => [7, String(v_n), [5, [0]]];

  const v_handler = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 348914022: {
          const v__b = __s[1];
          return [7, "EB", [5, [0]]];
        }
        case 502975519: {
          const v__u = __s[1];
          return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
        }
        case 589989748: {
          const v__s = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
  };

  const v_failIO = v_e => [6, v_e];

  const v_cont = v__args => v_failIO([24]);

  const v__io_getargs_cont = v_result => {
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

  const v__apply__lift_13 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 35: {
            return v__x;
          }
          case 36: {
            const v__pk_36 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_36;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_13 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_13(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_13(v__k, [6, [348914022, v___f0]]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 36, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_13(v__k, [8, [29, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_13 = v___input => v__cps__lift_13(v___input, [35]);

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 37: {
            return v__x;
          }
          case 38: {
            const v__pk_38 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_38;
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
            return v__apply__df_handleErrorIO_0(v__k, v_handler(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 38, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont_u0 = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [8, [25, v_cont_u0]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = v_io => v__cps__df_handleErrorIO_0(v_io, [37]);

  const v__apply__df__rowmono_4_bindIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 41: {
            return v__x;
          }
          case 42: {
            const v__pk_42 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_42;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_4_bindIO_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_4_bindIO_8(
              v__k,
              v__lift_13(v_cont(v_a))
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_4_bindIO_8(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 42, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont_u15 = __s[1];
            return v__apply__df__rowmono_4_bindIO_8(
              v__k,
              [8, [27, v_cont_u15]]
            );
          }
        }
      }
    }
  };

  const v__df__rowmono_4_bindIO_8 = v_io =>
    v__cps__df__rowmono_4_bindIO_8(v_io, [41]);

  const v__apply__df__rowmono_0_bindIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 39: {
            return v__x;
          }
          case 40: {
            const v__pk_40 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_40;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_0_bindIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_0_bindIO_4(v__k, v_showN(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_0_bindIO_4(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 40, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont_u9 = __s[1];
            return v__apply__df__rowmono_0_bindIO_4(v__k, [8, [26, v_cont_u9]]);
          }
        }
      }
    }
  };

  const v__df__rowmono_0_bindIO_4 = v_io =>
    v__cps__df__rowmono_0_bindIO_4(v_io, [39]);

  const v__apply__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14 = (
    v__k,
    v__x
  ) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 43: {
            return v__x;
          }
          case 44: {
            const v__pk_44 = __s[1];
            const __t0 = v__pk_44;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 45: {
            const v__pk_45 = __s[1];
            const __t0 = v__pk_45;
            const __t1 = v__df__rowmono_0_bindIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 46: {
            const v__pk_46 = __s[1];
            const __t0 = v__pk_46;
            const __t1 = v__df__rowmono_4_bindIO_8(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 47: {
            const v__pk_47 = __s[1];
            const __t0 = v__pk_47;
            const __t1 = v__lift_13(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 30: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 31, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 32, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 33, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 28: {
                  return v__apply__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14(
                    v__k,
                    v__io_getargs_cont(v__arg0)
                  );
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 34, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 31: {
            const v_cont_u18 = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 30, v__args[1] = v_cont_u18, v__args[2] = v_result, v__args);
            const __t1 = [44, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 32: {
            const v_cont_u6 = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 30, v__args[1] = v_cont_u6, v__args[2] = v_result, v__args);
            const __t1 = [45, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 33: {
            const v_cont_u12 = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 30, v__args[1] = v_cont_u12, v__args[2] = v_result, v__args);
            const __t1 = [46, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 34: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 30, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [47, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14 = v__args =>
    v__cps__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14(
      v__args,
      [43]
    );

  const v__apply1 = (v__cl, v__arg0) =>
    v__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14(
      [30, v__cl, v__arg0]
    );

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
          case 8: {
            const v_cont_u3 = __s[1];
            const __t0 = v__apply1(v_cont_u3, __getArgs());
            v_io = __t0;
            continue;
          }
        }
      }
    }
  };

  const main = v__df_handleErrorIO_0(
    v__df__rowmono_0_bindIO_4(v__df__rowmono_4_bindIO_8([8, [28]]))
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
