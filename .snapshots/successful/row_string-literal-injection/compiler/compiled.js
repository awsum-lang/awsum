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

  const v_sv = [1615808600, "S"];

  const v_pick = (v_b) => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 1: {
          return [1615808600, "T"];
        }
        case 2: {
          return [2711245919, 1 | 0];
        }
      }
    }
  };

  const v_iv = [2711245919, 9 | 0];

  const v_d = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1615808600: {
          const v_s = __s[1];
          return v_s;
        }
        case 2711245919: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v__let_13 = (v_lv) => {
    return v_d(v_lv);
  };

  const v_fromLet = (v__b) => {
    return v__let_13([1615808600, "L"]);
  };

  const v__lam_17 = (v__u) => {
    return [7, v_d(v_iv), [5, [0]]];
  };

  const v__lam_16 = (v__u) => {
    return [7, v_d(v_pick([1])), [5, [0]]];
  };

  const v__lam_15 = (v__u) => {
    return [7, v_d(v_pick([2])), [5, [0]]];
  };

  const v__lam_14 = (v__u) => {
    return [7, v_fromLet([1]), [5, [0]]];
  };

  const v__cps__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_3__df__lam_2_7 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 23: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 11: {
                  const v__cap11_0 = __s[1];
                  const __t0 = (v__args[0] = 24, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 12: {
                  const v__cap12_0 = __s[1];
                  const __t0 = (v__args[0] = 25, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 13: {
                  const v__cap13_0 = __s[1];
                  const __t0 = (v__args[0] = 26, v__args[1] = v__cap13_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 14: {
                  const v__cap14_0 = __s[1];
                  const __t0 = (v__args[0] = 27, v__args[1] = v__cap14_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 15: {
                  const v__cap15_0 = __s[1];
                  const __t0 = (v__args[0] = 28, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 16: {
                  const v__cap16_0 = __s[1];
                  const __t0 = (v__args[0] = 29, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 17: {
                  const v__cap17_0 = __s[1];
                  const __t0 = (v__args[0] = 30, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 18: {
                  const v__cap18_0 = __s[1];
                  const __t0 = (v__args[0] = 31, v__args[1] = v__cap18_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 19: {
                  const v__cap19_0 = __s[1];
                  const __t0 = (v__args[0] = 32, v__args[1] = v__cap19_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 20: {
                  const v__cap20_0 = __s[1];
                  const __t0 = (v__args[0] = 33, v__args[1] = v__cap20_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 21: {
                  const v__cap21_0 = __s[1];
                  const __t0 = (v__args[0] = 34, v__args[1] = v__cap21_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 22: {
                  const v__cap22_0 = __s[1];
                  const __t0 = (v__args[0] = 35, v__args[1] = v__cap22_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 24: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [45, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 25: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [46, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 26: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [47, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 27: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [48, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 28: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [49, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 29: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [50, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 30: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [51, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 31: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [52, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 32: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [53, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 33: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [54, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 34: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [55, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 35: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [56, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_3__df__lam_2_7 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_3__df__lam_2_7(
      v__args,
      [44]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_3__df__lam_2_7(
      [23, v__cl, v__arg0]
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

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 40: {
            return v__x;
          }
          case 41: {
            const v__pk_41 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_41;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_8(v__k, v__lam_16(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_8(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 41, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_8(v__k, [8, [14, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_8(v__k, [9, [15, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_8(v__k, [10, [19, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_8 = (v_io) => {
    return v__cps__df_andThenIO_8(v_io, [40]);
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 38: {
            return v__x;
          }
          case 39: {
            const v__pk_39 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_39;
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
            return v__apply__df_andThenIO_4(v__k, v__lam_15(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_4(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 39, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_4(v__k, [8, [13, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_4(v__k, [9, [18, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_4(v__k, [10, [22, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_4 = (v_io) => {
    return v__cps__df_andThenIO_4(v_io, [38]);
  };

  const v__apply__df_andThenIO_12 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 42: {
            return v__x;
          }
          case 43: {
            const v__pk_43 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_43;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_12 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_12(v__k, v__lam_17(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_12(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 43, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_12(v__k, [8, [12, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_12(v__k, [9, [16, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_12(v__k, [10, [20, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_12 = (v_io) => {
    return v__cps__df_andThenIO_12(v_io, [42]);
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 36: {
            return v__x;
          }
          case 37: {
            const v__pk_37 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_37;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_0(v__k, v__lam_14(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_0(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 37, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_0(v__k, [8, [11, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_0(v__k, [9, [17, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_0(v__k, [10, [21, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_0 = (v_io) => {
    return v__cps__df_andThenIO_0(v_io, [36]);
  };

  const main = v__df_andThenIO_0(
    v__df_andThenIO_4(
      v__df_andThenIO_8(v__df_andThenIO_12([7, v_d(v_sv), [5, [0]]]))
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
