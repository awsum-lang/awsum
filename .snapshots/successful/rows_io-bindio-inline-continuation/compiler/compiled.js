"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
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

  const __stdinReadAllBytes = () => {
    const buf = require("fs").readFileSync(0);
    let list = [13];
    for (let i = buf.length - 1; i >= 0; i--) {
      list = [14, buf[i], list];
    }
    return list;
  };

  const v_handler = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 502975519: {
          const v__u = __s[1];
          return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
        }
        case 589989748: {
          const v__s = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 718021640: {
          const v__x = __s[1];
          return [7, "EX", [5, [0]]];
        }
      }
    }
  };

  const v_failIO = (v_e) => {
    return [6, v_e];
  };

  const v__lam_13 = (v__args) => {
    return v_failIO([718021640, [24]]);
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

  const v__apply__df_handleErrorIO_4 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_4(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_4(v__k, v_handler(v_e));
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
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_4(v__k, [8, [27, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_4(v__k, [9, [25, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_4(v__k, [10, [26, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_4 = (v_io) => {
    return v__cps__df_handleErrorIO_4(v_io, [41]);
  };

  const v__apply__df__rowmono_0_bindIO_0 = (v__k, v__x) => {
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

  const v__cps__df__rowmono_0_bindIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_0_bindIO_0(v__k, v__lam_13(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_0_bindIO_0(v__k, [6, v_e]);
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
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_bindIO_0(v__k, [8, [28, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_bindIO_0(v__k, [9, [29, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_bindIO_0(v__k, [10, [30, v_cont]]);
          }
        }
      }
    }
  };

  const v__df__rowmono_0_bindIO_0 = (v_io) => {
    return v__cps__df__rowmono_0_bindIO_0(v_io, [39]);
  };

  const v__apply__scc__apply1__df__lam_10_6__df__lam_11_7__df__lam_9_5__df__rowmono_1_bindIOAfterArgs_1__df__rowmono_2_bindIOAfterStdinString_2__df__rowmono_3_bindIOAfterStdinBytes_3 = (
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
            const __t1 = v__df_handleErrorIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 45: {
            const v__pk_45 = __s[1];
            const __t0 = v__pk_45;
            const __t1 = v__df_handleErrorIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 46: {
            const v__pk_46 = __s[1];
            const __t0 = v__pk_46;
            const __t1 = v__df_handleErrorIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 47: {
            const v__pk_47 = __s[1];
            const __t0 = v__pk_47;
            const __t1 = v__df__rowmono_0_bindIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 48: {
            const v__pk_48 = __s[1];
            const __t0 = v__pk_48;
            const __t1 = v__df__rowmono_0_bindIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 49: {
            const v__pk_49 = __s[1];
            const __t0 = v__pk_49;
            const __t1 = v__df__rowmono_0_bindIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_10_6__df__lam_11_7__df__lam_9_5__df__rowmono_1_bindIOAfterArgs_1__df__rowmono_2_bindIOAfterStdinString_2__df__rowmono_3_bindIOAfterStdinBytes_3 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 32: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 33, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 34, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 35, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 28: {
                  const v__cap28_0 = __s[1];
                  const __t0 = (v__args[0] = 36, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 37, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 38, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 31: {
                  return v__apply__scc__apply1__df__lam_10_6__df__lam_11_7__df__lam_9_5__df__rowmono_1_bindIOAfterArgs_1__df__rowmono_2_bindIOAfterStdinString_2__df__rowmono_3_bindIOAfterStdinBytes_3(
                    v__k,
                    v__io_getargs_cont(v__arg0)
                  );
                }
              }
            }
          }
          case 33: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [44, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 34: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [45, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 35: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [46, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 36: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [47, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 37: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [48, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 38: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [49, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_10_6__df__lam_11_7__df__lam_9_5__df__rowmono_1_bindIOAfterArgs_1__df__rowmono_2_bindIOAfterStdinString_2__df__rowmono_3_bindIOAfterStdinBytes_3 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_10_6__df__lam_11_7__df__lam_9_5__df__rowmono_1_bindIOAfterArgs_1__df__rowmono_2_bindIOAfterStdinString_2__df__rowmono_3_bindIOAfterStdinBytes_3(
      v__args,
      [43]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_10_6__df__lam_11_7__df__lam_9_5__df__rowmono_1_bindIOAfterArgs_1__df__rowmono_2_bindIOAfterStdinString_2__df__rowmono_3_bindIOAfterStdinBytes_3(
      [32, v__cl, v__arg0]
    );
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
          case 9: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __stdinReadAll());
            v_io = __t0;
            continue;
          }
          case 10: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __stdinReadAllBytes());
            v_io = __t0;
            continue;
          }
        }
      }
    }
  };

  const v_combined = v__df__rowmono_0_bindIO_0([8, [31]]);

  const main = v__df_handleErrorIO_4(v_combined);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
