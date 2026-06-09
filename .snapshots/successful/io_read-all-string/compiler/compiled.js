"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __stdinReadAll = () => {
    let s;
    try {
      s = new TextDecoder("utf-8", {fatal: true, ignoreBOM: true}).decode(
        require("fs").readFileSync(0)
      );
    } catch (e) {
      return [3, [3239958583, [21]]];
    }
    if (s.length > 134217728) {
      return [3, [589989748, [19]]];
    }
    return [4, s];
  };

  const v_handleErr = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 589989748: {
          const v__l = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 3239958583: {
          const v__i = __s[1];
          return [7, "INVALID_UTF8", [5, [0]]];
        }
      }
    }
  };

  const v__io_stdinReadAllString_cont = v_result => {
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

  const v__bi_IO_Stdout_print = v__x0 => [7, v__x0, [5, [0]]];

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 16: {
            return v__x;
          }
          case 17: {
            const v__pk_17 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_17;
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
            return v__apply__df_handleErrorIO_0(v__k, v_handleErr(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 17, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [9, [10, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = v_io => v__cps__df_handleErrorIO_0(v_io, [16]);

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 18: {
            return v__x;
          }
          case 19: {
            const v__pk_19 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_19;
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
              v__bi_IO_Stdout_print(v_a)
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
            const __t1 = (v_io[0] = 19, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [9, [11, v_cont]]);
          }
        }
      }
    }
  };

  const v__df__rowmono_0_andThenIO_4 = v_io =>
    v__cps__df__rowmono_0_andThenIO_4(v_io, [18]);

  const v__apply__scc__apply1__df__lam_10_2__df__lam_14_6 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 20: {
            return v__x;
          }
          case 21: {
            const v__pk_21 = __s[1];
            const __t0 = v__pk_21;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 22: {
            const v__pk_22 = __s[1];
            const __t0 = v__pk_22;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_10_2__df__lam_14_6 = (v__args, v__k) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 13: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 10: {
                  const v__cap10_0 = __s[1];
                  const __t0 = (v__args[0] = 14, v__args[1] = v__cap10_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 11: {
                  const v__cap11_0 = __s[1];
                  const __t0 = (v__args[0] = 15, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 12: {
                  return v__apply__scc__apply1__df__lam_10_2__df__lam_14_6(
                    v__k,
                    v__io_stdinReadAllString_cont(v__arg0)
                  );
                }
              }
            }
          }
          case 14: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 13, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [21, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 15: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 13, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [22, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_10_2__df__lam_14_6 = v__args =>
    v__cps__scc__apply1__df__lam_10_2__df__lam_14_6(v__args, [20]);

  const v__apply1 = (v__cl, v__arg0) =>
    v__scc__apply1__df__lam_10_2__df__lam_14_6([13, v__cl, v__arg0]);

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
          case 9: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __stdinReadAll());
            v_io = __t0;
            continue;
          }
        }
      }
    }
  };

  const main = v__df_handleErrorIO_0(v__df__rowmono_0_andThenIO_4([9, [12]]));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
