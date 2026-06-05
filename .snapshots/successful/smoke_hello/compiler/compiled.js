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

  const v__lift_45 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 11: {
          return [11];
        }
        case 12: {
          const v___f0 = __s[1];
          return [12, v___f0];
        }
      }
    }
  };

  const v_greet = (v_args) => {
    {
      const __s = v_nothingAsLeft([24], v__lift_45(v_headList(v_args)));
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
                return __concat(v_hello, "!");
              }
            }
          }
        }
      }
    }
  };

  const v__lift_43 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, v___f0];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
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

  const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
  };

  const v__apply__lift_36 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 89: {
            return v__x;
          }
          case 90: {
            const v__pk_90 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_90;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_36 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_36(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_36(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 90, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_36(v__k, [8, [49, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_36(v__k, [9, [50, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_36(v__k, [10, [51, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_36 = (v___input) => {
    return v__cps__lift_36(v___input, [89]);
  };

  const v__apply__lift_28 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 87: {
            return v__x;
          }
          case 88: {
            const v__pk_88 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_88;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_28 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_28(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_28(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 88, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_28(v__k, [8, [45, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_28(v__k, [9, [47, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_28(v__k, [10, [48, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_28 = (v___input) => {
    return v__cps__lift_28(v___input, [87]);
  };

  const v__apply__lift_24 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 85: {
            return v__x;
          }
          case 86: {
            const v__pk_86 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_86;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_24 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [6, [3801428867, v___f0]]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 86, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [8, [42, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [9, [43, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [10, [44, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_24 = (v___input) => {
    return v__cps__lift_24(v___input, [85]);
  };

  const v__apply__lift_17 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 83: {
            return v__x;
          }
          case 84: {
            const v__pk_84 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_84;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_17 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_17(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_17(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 84, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_17(v__k, [8, [38, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_17(v__k, [9, [39, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_17(v__k, [10, [41, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_17 = (v___input) => {
    return v__cps__lift_17(v___input, [83]);
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
          return v__lift_17(v_pureIO(v_a));
        }
      }
    }
  };

  const v__lam_44 = (v_args) => {
    return v_eitherToIO(v__lift_43(v_greet(v_args)));
  };

  const v__apply__lift_1 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 81: {
            return v__x;
          }
          case 82: {
            const v__pk_82 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_82;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_1 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 82, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [8, [40, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [9, [46, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [10, [52, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_1 = (v___input) => {
    return v__cps__lift_1(v___input, [81]);
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 91: {
            return v__x;
          }
          case 92: {
            const v__pk_92 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_92;
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
            const __t1 = (v_io[0] = 92, v_io[1] = v__k, v_io[2] = v_s, v_io);
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
    return v__cps__df_handleErrorIO_0(v_io, [91]);
  };

  const v__apply__df_andThenIO_10 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 95: {
            return v__x;
          }
          case 96: {
            const v__pk_96 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_96;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_10 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_10(v__k, v__lift_1(v__lam_44(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_10(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 96, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_10(v__k, [8, [34, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_10(v__k, [9, [35, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_10(v__k, [10, [36, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_10 = (v_io) => {
    return v__cps__df_andThenIO_10(v_io, [95]);
  };

  const v__apply__df__rowspec_35_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 97: {
            return v__x;
          }
          case 98: {
            const v__pk_98 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_98;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowspec_35_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowspec_35_8(v__k, v__lam_44(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowspec_35_8(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 98, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowspec_35_8(v__k, [8, [31, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowspec_35_8(v__k, [9, [32, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowspec_35_8(v__k, [10, [33, v_cont]]);
          }
        }
      }
    }
  };

  const v__df__rowspec_35_8 = (v_io) => {
    return v__cps__df__rowspec_35_8(v_io, [97]);
  };

  const v__apply__df__rowspec_23_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 93: {
            return v__x;
          }
          case 94: {
            const v__pk_94 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_94;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowspec_23_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowspec_23_4(
              v__k,
              v__lift_24(v__bi_IO_Stdout_print(v_a))
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowspec_23_4(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 94, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowspec_23_4(v__k, [8, [28, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowspec_23_4(v__k, [9, [29, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowspec_23_4(v__k, [10, [30, v_cont]]);
          }
        }
      }
    }
  };

  const v__df__rowspec_23_4 = (v_io) => {
    return v__cps__df__rowspec_23_4(v_io, [93]);
  };

  const v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4 = (
    v__k,
    v__x
  ) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 99: {
            return v__x;
          }
          case 100: {
            const v__pk_100 = __s[1];
            const __t0 = v__pk_100;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 101: {
            const v__pk_101 = __s[1];
            const __t0 = v__pk_101;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 102: {
            const v__pk_102 = __s[1];
            const __t0 = v__pk_102;
            const __t1 = v__df_handleErrorIO_0(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 103: {
            const v__pk_103 = __s[1];
            const __t0 = v__pk_103;
            const __t1 = v__df__rowspec_23_4(v__lift_28(v__x));
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 104: {
            const v__pk_104 = __s[1];
            const __t0 = v__pk_104;
            const __t1 = v__df__rowspec_23_4(v__lift_28(v__x));
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 105: {
            const v__pk_105 = __s[1];
            const __t0 = v__pk_105;
            const __t1 = v__df__rowspec_23_4(v__lift_28(v__x));
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 106: {
            const v__pk_106 = __s[1];
            const __t0 = v__pk_106;
            const __t1 = v__df_andThenIO_10(v__lift_36(v__x));
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 107: {
            const v__pk_107 = __s[1];
            const __t0 = v__pk_107;
            const __t1 = v__df_andThenIO_10(v__lift_36(v__x));
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 108: {
            const v__pk_108 = __s[1];
            const __t0 = v__pk_108;
            const __t1 = v__df_andThenIO_10(v__lift_36(v__x));
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 109: {
            const v__pk_109 = __s[1];
            const __t0 = v__pk_109;
            const __t1 = v__df_andThenIO_10(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 110: {
            const v__pk_110 = __s[1];
            const __t0 = v__pk_110;
            const __t1 = v__df_andThenIO_10(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 111: {
            const v__pk_111 = __s[1];
            const __t0 = v__pk_111;
            const __t1 = v__df_andThenIO_10(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 112: {
            const v__pk_112 = __s[1];
            const __t0 = v__pk_112;
            const __t1 = v__lift_17(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 113: {
            const v__pk_113 = __s[1];
            const __t0 = v__pk_113;
            const __t1 = v__lift_17(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 114: {
            const v__pk_114 = __s[1];
            const __t0 = v__pk_114;
            const __t1 = v__lift_1(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 115: {
            const v__pk_115 = __s[1];
            const __t0 = v__pk_115;
            const __t1 = v__lift_17(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 116: {
            const v__pk_116 = __s[1];
            const __t0 = v__pk_116;
            const __t1 = v__lift_24(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 117: {
            const v__pk_117 = __s[1];
            const __t0 = v__pk_117;
            const __t1 = v__lift_24(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 118: {
            const v__pk_118 = __s[1];
            const __t0 = v__pk_118;
            const __t1 = v__lift_24(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 119: {
            const v__pk_119 = __s[1];
            const __t0 = v__pk_119;
            const __t1 = v__lift_28(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 120: {
            const v__pk_120 = __s[1];
            const __t0 = v__pk_120;
            const __t1 = v__lift_1(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 121: {
            const v__pk_121 = __s[1];
            const __t0 = v__pk_121;
            const __t1 = v__lift_28(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 122: {
            const v__pk_122 = __s[1];
            const __t0 = v__pk_122;
            const __t1 = v__lift_28(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 123: {
            const v__pk_123 = __s[1];
            const __t0 = v__pk_123;
            const __t1 = v__lift_36(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 124: {
            const v__pk_124 = __s[1];
            const __t0 = v__pk_124;
            const __t1 = v__lift_36(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 125: {
            const v__pk_125 = __s[1];
            const __t0 = v__pk_125;
            const __t1 = v__lift_36(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 126: {
            const v__pk_126 = __s[1];
            const __t0 = v__pk_126;
            const __t1 = v__lift_1(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 53: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 54, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 55, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 56, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 28: {
                  const v__cap28_0 = __s[1];
                  const __t0 = (v__args[0] = 57, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 58, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 59, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 31: {
                  const v__cap31_0 = __s[1];
                  const __t0 = (v__args[0] = 60, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 32: {
                  const v__cap32_0 = __s[1];
                  const __t0 = (v__args[0] = 61, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 33: {
                  const v__cap33_0 = __s[1];
                  const __t0 = (v__args[0] = 62, v__args[1] = v__cap33_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 34: {
                  const v__cap34_0 = __s[1];
                  const __t0 = (v__args[0] = 63, v__args[1] = v__cap34_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 35: {
                  const v__cap35_0 = __s[1];
                  const __t0 = (v__args[0] = 64, v__args[1] = v__cap35_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 36: {
                  const v__cap36_0 = __s[1];
                  const __t0 = (v__args[0] = 65, v__args[1] = v__cap36_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 37: {
                  return v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(
                    v__k,
                    v__io_getargs_cont(v__arg0)
                  );
                }
                case 38: {
                  const v__cap38_0 = __s[1];
                  const __t0 = (v__args[0] = 66, v__args[1] = v__cap38_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 39: {
                  const v__cap39_0 = __s[1];
                  const __t0 = (v__args[0] = 67, v__args[1] = v__cap39_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 40: {
                  const v__cap40_0 = __s[1];
                  const __t0 = (v__args[0] = 68, v__args[1] = v__cap40_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 41: {
                  const v__cap41_0 = __s[1];
                  const __t0 = (v__args[0] = 69, v__args[1] = v__cap41_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 42: {
                  const v__cap42_0 = __s[1];
                  const __t0 = (v__args[0] = 70, v__args[1] = v__cap42_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 43: {
                  const v__cap43_0 = __s[1];
                  const __t0 = (v__args[0] = 71, v__args[1] = v__cap43_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 44: {
                  const v__cap44_0 = __s[1];
                  const __t0 = (v__args[0] = 72, v__args[1] = v__cap44_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 45: {
                  const v__cap45_0 = __s[1];
                  const __t0 = (v__args[0] = 73, v__args[1] = v__cap45_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 46: {
                  const v__cap46_0 = __s[1];
                  const __t0 = (v__args[0] = 74, v__args[1] = v__cap46_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 47: {
                  const v__cap47_0 = __s[1];
                  const __t0 = (v__args[0] = 75, v__args[1] = v__cap47_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 48: {
                  const v__cap48_0 = __s[1];
                  const __t0 = (v__args[0] = 76, v__args[1] = v__cap48_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 49: {
                  const v__cap49_0 = __s[1];
                  const __t0 = (v__args[0] = 77, v__args[1] = v__cap49_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 50: {
                  const v__cap50_0 = __s[1];
                  const __t0 = (v__args[0] = 78, v__args[1] = v__cap50_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 51: {
                  const v__cap51_0 = __s[1];
                  const __t0 = (v__args[0] = 79, v__args[1] = v__cap51_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 52: {
                  const v__cap52_0 = __s[1];
                  const __t0 = (v__args[0] = 80, v__args[1] = v__cap52_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 54: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [100, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 55: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [101, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 56: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [102, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 57: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [103, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 58: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [104, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 59: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [105, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 60: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [106, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 61: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [107, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 62: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [108, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 63: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [109, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 64: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [110, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 65: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [111, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 66: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [112, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 67: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [113, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 68: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [114, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 69: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [115, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 70: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [116, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 71: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [117, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 72: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [118, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 73: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [119, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 74: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [120, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 75: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [121, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 76: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [122, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 77: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [123, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 78: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [124, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 79: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [125, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 80: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 53, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [126, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(
      v__args,
      [99]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(
      [53, v__cl, v__arg0]
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
    v__df__rowspec_23_4(v__lift_28(v__df__rowspec_35_8([8, [37]])))
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
