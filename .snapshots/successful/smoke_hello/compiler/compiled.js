"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
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

  const v_pureIO = (v_x) => {
    return [5, v_x];
  };

  const v_printError = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 502975519: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 20: {
                return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
              }
            }
          }
        }
        case 589989748: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 19: {
                return [7, "STRING_TOO_LONG", [5, [0]]];
              }
            }
          }
        }
        case 3864168810: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 24: {
                return [7, "NO_ARG", [5, [0]]];
              }
            }
          }
        }
      }
    }
  };

  const v_nothingAsLeft = (v_e, v_m) => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 11: {
          return [3, v_e];
        }
        case 12: {
          const v_a = __s[1];
          return [4, v_a];
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

  const v__lift_14 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [589989748, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v_greet = (v_args) => {
    {
      const __s = v_nothingAsLeft([24], v_headList(v_args));
      switch (__s[0]) {
        case 3: {
          const v__do_e_1 = __s[1];
          return [3, [3864168810, v__do_e_1]];
        }
        case 4: {
          const v_name = __s[1];
          {
            const __s = __concat("Hello, ", v_name);
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                return [3, [589989748, v__do_e_0]];
              }
              case 4: {
                const v_hello = __s[1];
                return v__lift_14(__concat(v_hello, "!"));
              }
            }
          }
        }
      }
    }
  };

  const v__lam_13 = (v_args) => {
    return v_eitherToIO(v_greet(v_args));
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

  const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 45: {
            return v__x;
          }
          case 46: {
            const v__pk_46 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_46;
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
            return v__apply__df_handleErrorIO_0(v__k, v_printError(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 46, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [8, [33, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [9, [25, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [10, [26, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = (v_io) => {
    return v__cps__df_handleErrorIO_0(v_io, [45]);
  };

  const v__apply__df__rowmono_1_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 49: {
            return v__x;
          }
          case 50: {
            const v__pk_50 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_50;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_1_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(v__k, v__lam_13(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 50, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(v__k, [8, [30, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(v__k, [9, [31, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(
              v__k,
              [10, [32, v_cont]]
            );
          }
        }
      }
    }
  };

  const v__df__rowmono_1_andThenIO_8 = (v_io) => {
    return v__cps__df__rowmono_1_andThenIO_8(v_io, [49]);
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 47: {
            return v__x;
          }
          case 48: {
            const v__pk_48 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_48;
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
            const __t1 = (v_io[0] = 48, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [8, [27, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [9, [28, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(
              v__k,
              [10, [29, v_cont]]
            );
          }
        }
      }
    }
  };

  const v__df__rowmono_0_andThenIO_4 = (v_io) => {
    return v__cps__df__rowmono_0_andThenIO_4(v_io, [47]);
  };

  const v__apply__scc__apply1__df__lam_10_2__df__lam_11_3__df__lam_15_5__df__lam_16_6__df__lam_17_7__df__lam_18_9__df__lam_19_10__df__lam_20_11__df__lam_9_1 = (
    v__k,
    v__x
  ) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 51: {
            return v__x;
          }
          case 52: {
            const v__pk_52 = __s[1];
            const __t0 = v__pk_52;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 53: {
            const v__pk_53 = __s[1];
            const __t0 = v__pk_53;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 54: {
            const v__pk_54 = __s[1];
            const __t0 = v__pk_54;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 55: {
            const v__pk_55 = __s[1];
            const __t0 = v__pk_55;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 56: {
            const v__pk_56 = __s[1];
            const __t0 = v__pk_56;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 57: {
            const v__pk_57 = __s[1];
            const __t0 = v__pk_57;
            const __t1 = v__df__rowmono_1_andThenIO_8(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 58: {
            const v__pk_58 = __s[1];
            const __t0 = v__pk_58;
            const __t1 = v__df__rowmono_1_andThenIO_8(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 59: {
            const v__pk_59 = __s[1];
            const __t0 = v__pk_59;
            const __t1 = v__df__rowmono_1_andThenIO_8(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 60: {
            const v__pk_60 = __s[1];
            const __t0 = v__pk_60;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_10_2__df__lam_11_3__df__lam_15_5__df__lam_16_6__df__lam_17_7__df__lam_18_9__df__lam_19_10__df__lam_20_11__df__lam_9_1 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 35: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 36, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 37, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 38, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 28: {
                  const v__cap28_0 = __s[1];
                  const __t0 = (v__args[0] = 39, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 40, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 41, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 31: {
                  const v__cap31_0 = __s[1];
                  const __t0 = (v__args[0] = 42, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 32: {
                  const v__cap32_0 = __s[1];
                  const __t0 = (v__args[0] = 43, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 33: {
                  const v__cap33_0 = __s[1];
                  const __t0 = (v__args[0] = 44, v__args[1] = v__cap33_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 34: {
                  return v__apply__scc__apply1__df__lam_10_2__df__lam_11_3__df__lam_15_5__df__lam_16_6__df__lam_17_7__df__lam_18_9__df__lam_19_10__df__lam_20_11__df__lam_9_1(
                    v__k,
                    v__io_getargs_cont(v__arg0)
                  );
                }
              }
            }
          }
          case 36: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [52, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 37: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [53, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 38: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [54, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 39: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [55, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 40: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [56, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 41: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [57, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 42: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [58, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 43: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [59, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 44: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 35, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [60, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_10_2__df__lam_11_3__df__lam_15_5__df__lam_16_6__df__lam_17_7__df__lam_18_9__df__lam_19_10__df__lam_20_11__df__lam_9_1 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_10_2__df__lam_11_3__df__lam_15_5__df__lam_16_6__df__lam_17_7__df__lam_18_9__df__lam_19_10__df__lam_20_11__df__lam_9_1(
      v__args,
      [51]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_10_2__df__lam_11_3__df__lam_15_5__df__lam_16_6__df__lam_17_7__df__lam_18_9__df__lam_19_10__df__lam_20_11__df__lam_9_1(
      [35, v__cl, v__arg0]
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

  const main = v__df_handleErrorIO_0(
    v__df__rowmono_0_andThenIO_4(v__df__rowmono_1_andThenIO_8([8, [34]]))
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
