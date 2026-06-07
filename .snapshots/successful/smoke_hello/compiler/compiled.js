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

  const v__lift_19 = (v___input) => {
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
                return v__lift_19(__concat(v_hello, "!"));
              }
            }
          }
        }
      }
    }
  };

  const v__lam_18 = (v_args) => {
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

  const v__apply__lift_27 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 59: {
            return v__x;
          }
          case 60: {
            const v__pk_60 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_60;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_27 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_27(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_27(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 60, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_27(v__k, [8, [38, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_27(v__k, [9, [39, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_27(v__k, [10, [40, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_27 = (v___input) => {
    return v__cps__lift_27(v___input, [59]);
  };

  const v__apply__lift_20 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 57: {
            return v__x;
          }
          case 58: {
            const v__pk_58 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_58;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_20 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_20(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_20(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 58, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_20(v__k, [8, [35, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_20(v__k, [9, [36, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_20(v__k, [10, [37, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_20 = (v___input) => {
    return v__cps__lift_20(v___input, [57]);
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 61: {
            return v__x;
          }
          case 62: {
            const v__pk_62 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_62;
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
            const __t1 = (v_io[0] = 62, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [8, [25, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [9, [26, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [10, [27, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = (v_io) => {
    return v__cps__df_handleErrorIO_0(v_io, [61]);
  };

  const v__apply__df__rowmono_1_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 65: {
            return v__x;
          }
          case 66: {
            const v__pk_66 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_66;
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
            return v__apply__df__rowmono_1_andThenIO_8(
              v__k,
              v__lift_27(v__lam_18(v_a))
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 66, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(v__k, [8, [31, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(v__k, [9, [32, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(
              v__k,
              [10, [33, v_cont]]
            );
          }
        }
      }
    }
  };

  const v__df__rowmono_1_andThenIO_8 = (v_io) => {
    return v__cps__df__rowmono_1_andThenIO_8(v_io, [65]);
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 63: {
            return v__x;
          }
          case 64: {
            const v__pk_64 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_64;
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
              v__lift_20(v__bi_IO_Stdout_print(v_a))
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
            const __t1 = (v_io[0] = 64, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [8, [28, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [9, [29, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(
              v__k,
              [10, [30, v_cont]]
            );
          }
        }
      }
    }
  };

  const v__df__rowmono_0_andThenIO_4 = (v_io) => {
    return v__cps__df__rowmono_0_andThenIO_4(v_io, [63]);
  };

  const v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30 = (
    v__k,
    v__x
  ) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 67: {
            return v__x;
          }
          case 68: {
            const v__pk_68 = __s[1];
            const __t0 = v__pk_68;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 69: {
            const v__pk_69 = __s[1];
            const __t0 = v__pk_69;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 70: {
            const v__pk_70 = __s[1];
            const __t0 = v__pk_70;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 71: {
            const v__pk_71 = __s[1];
            const __t0 = v__pk_71;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 72: {
            const v__pk_72 = __s[1];
            const __t0 = v__pk_72;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 73: {
            const v__pk_73 = __s[1];
            const __t0 = v__pk_73;
            const __t1 = v__df__rowmono_0_andThenIO_4(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 74: {
            const v__pk_74 = __s[1];
            const __t0 = v__pk_74;
            const __t1 = v__df__rowmono_1_andThenIO_8(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 75: {
            const v__pk_75 = __s[1];
            const __t0 = v__pk_75;
            const __t1 = v__df__rowmono_1_andThenIO_8(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 76: {
            const v__pk_76 = __s[1];
            const __t0 = v__pk_76;
            const __t1 = v__df__rowmono_1_andThenIO_8(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 77: {
            const v__pk_77 = __s[1];
            const __t0 = v__pk_77;
            const __t1 = v__lift_20(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 78: {
            const v__pk_78 = __s[1];
            const __t0 = v__pk_78;
            const __t1 = v__lift_20(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 79: {
            const v__pk_79 = __s[1];
            const __t0 = v__pk_79;
            const __t1 = v__lift_20(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 80: {
            const v__pk_80 = __s[1];
            const __t0 = v__pk_80;
            const __t1 = v__lift_27(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 81: {
            const v__pk_81 = __s[1];
            const __t0 = v__pk_81;
            const __t1 = v__lift_27(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 82: {
            const v__pk_82 = __s[1];
            const __t0 = v__pk_82;
            const __t1 = v__lift_27(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 41: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 42, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 43, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 44, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 28: {
                  const v__cap28_0 = __s[1];
                  const __t0 = (v__args[0] = 45, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 46, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 47, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 31: {
                  const v__cap31_0 = __s[1];
                  const __t0 = (v__args[0] = 48, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 32: {
                  const v__cap32_0 = __s[1];
                  const __t0 = (v__args[0] = 49, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 33: {
                  const v__cap33_0 = __s[1];
                  const __t0 = (v__args[0] = 50, v__args[1] = v__cap33_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 34: {
                  return v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(
                    v__k,
                    v__io_getargs_cont(v__arg0)
                  );
                }
                case 35: {
                  const v__cap35_0 = __s[1];
                  const __t0 = (v__args[0] = 51, v__args[1] = v__cap35_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 36: {
                  const v__cap36_0 = __s[1];
                  const __t0 = (v__args[0] = 52, v__args[1] = v__cap36_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 37: {
                  const v__cap37_0 = __s[1];
                  const __t0 = (v__args[0] = 53, v__args[1] = v__cap37_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 38: {
                  const v__cap38_0 = __s[1];
                  const __t0 = (v__args[0] = 54, v__args[1] = v__cap38_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 39: {
                  const v__cap39_0 = __s[1];
                  const __t0 = (v__args[0] = 55, v__args[1] = v__cap39_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 40: {
                  const v__cap40_0 = __s[1];
                  const __t0 = (v__args[0] = 56, v__args[1] = v__cap40_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 42: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [68, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 43: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [69, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 44: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [70, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 45: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [71, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 46: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [72, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 47: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [73, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 48: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [74, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 49: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [75, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 50: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [76, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 51: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [77, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 52: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [78, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 53: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [79, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 54: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [80, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 55: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [81, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 56: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 41, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [82, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(
      v__args,
      [67]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(
      [41, v__cl, v__arg0]
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
