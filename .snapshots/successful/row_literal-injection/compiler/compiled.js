"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqInt32 = (a, b) => {
    return a === b ? [1] : [2];
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

  const v_gU = (v_n) => {
    {
      const __s = __eqInt32(v_n, 0 | 0);
      switch (__s[0]) {
        case 1: {
          return [3538687084, 11 >>> 0];
        }
        case 2: {
          return [3538687084, 13 >>> 0];
        }
      }
    }
  };

  const v_gBare = (v_n) => {
    {
      const __s = __eqInt32(v_n, 0 | 0);
      switch (__s[0]) {
        case 1: {
          return [2711245919, 7 | 0];
        }
        case 2: {
          return [2711245919, 9 | 0];
        }
      }
    }
  };

  const v_gAsc = (v_n) => {
    {
      const __s = __eqInt32(v_n, 0 | 0);
      switch (__s[0]) {
        case 1: {
          return [2711245919, 7 | 0];
        }
        case 2: {
          return [2711245919, 9 | 0];
        }
      }
    }
  };

  const v_extractU = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3538687084: {
          const v_n = __s[1];
          return v_n;
        }
      }
    }
  };

  const v_extract = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 2711245919: {
          const v_n = __s[1];
          return v_n;
        }
      }
    }
  };

  const v__lam_23 = (v__u) => {
    return [7, String(v_extractU(v_gU(1 | 0))), [5, [0]]];
  };

  const v__cps__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_17__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_18__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_19__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4 = (
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
                case 11: {
                  const v__cap11_0 = __s[1];
                  const __t0 = (v__args[0] = 33, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 12: {
                  const v__cap12_0 = __s[1];
                  const __t0 = (v__args[0] = 34, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 13: {
                  const v__cap13_0 = __s[1];
                  const __t0 = (v__args[0] = 35, v__args[1] = v__cap13_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 14: {
                  const v__cap14_0 = __s[1];
                  const __t0 = (v__args[0] = 36, v__args[1] = v__cap14_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 15: {
                  const v__cap15_0 = __s[1];
                  const __t0 = (v__args[0] = 37, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 16: {
                  const v__cap16_0 = __s[1];
                  const __t0 = (v__args[0] = 38, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 17: {
                  const v__cap17_0 = __s[1];
                  const __t0 = (v__args[0] = 39, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 18: {
                  const v__cap18_0 = __s[1];
                  const __t0 = (v__args[0] = 40, v__args[1] = v__cap18_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 19: {
                  const v__cap19_0 = __s[1];
                  const __t0 = (v__args[0] = 41, v__args[1] = v__cap19_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 20: {
                  const v__cap20_0 = __s[1];
                  const __t0 = (v__args[0] = 42, v__args[1] = v__cap20_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 21: {
                  const v__cap21_0 = __s[1];
                  const __t0 = (v__args[0] = 43, v__args[1] = v__cap21_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 22: {
                  const v__cap22_0 = __s[1];
                  const __t0 = (v__args[0] = 44, v__args[1] = v__cap22_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 23: {
                  const v__cap23_0 = __s[1];
                  const __t0 = (v__args[0] = 45, v__args[1] = v__cap23_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 24: {
                  const v__cap24_0 = __s[1];
                  const __t0 = (v__args[0] = 46, v__args[1] = v__cap24_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 47, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 48, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 49, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 28: {
                  const v__cap28_0 = __s[1];
                  const __t0 = (v__args[0] = 50, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 51, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 52, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 31: {
                  const v__cap31_0 = __s[1];
                  const __t0 = (v__args[0] = 53, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 33: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [69, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 34: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [70, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 35: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [71, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 36: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [72, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 37: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [73, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 38: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [74, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 39: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [75, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 40: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [76, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 41: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [77, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 42: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [78, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 43: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [79, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 44: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [80, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 45: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [81, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 46: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [82, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 47: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [83, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 48: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [84, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 49: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [85, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 50: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [86, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 51: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [87, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 52: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [88, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 53: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 32, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [89, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_17__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_18__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_19__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_17__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_18__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_19__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4(
      v__args,
      [68]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_17__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_18__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_19__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4(
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

  const v__apply__lift_24 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 56: {
            return v__x;
          }
          case 57: {
            const v__pk_57 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_57;
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
            return v__apply__lift_24(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 57, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [8, [27, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [9, [28, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_24(v__k, [10, [29, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_24 = (v___input) => {
    return v__cps__lift_24(v___input, [56]);
  };

  const v__lam_28 = (v__u) => {
    return v__lift_24([7, String(v_extractU(v_gU(0 | 0))), [5, [0]]]);
  };

  const v__lam_29 = (v__u) => {
    return v__lift_24([7, String(v_extract(v_gBare(1 | 0))), [5, [0]]]);
  };

  const v__lam_30 = (v__u) => {
    return v__lift_24([7, String(v_extract(v_gBare(0 | 0))), [5, [0]]]);
  };

  const v__lam_31 = (v__u) => {
    return v__lift_24([7, String(v_extract(v_gAsc(1 | 0))), [5, [0]]]);
  };

  const v__apply__lift_1 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 54: {
            return v__x;
          }
          case 55: {
            const v__pk_55 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_55;
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
            const __t1 = (v___input[0] = 55, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [8, [26, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [9, [30, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [10, [31, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_1 = (v___input) => {
    return v__cps__lift_1(v___input, [54]);
  };

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 62: {
            return v__x;
          }
          case 63: {
            const v__pk_63 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_63;
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
            return v__apply__df_andThenIO_8(v__k, v__lift_1(v__lam_29(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_8(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 63, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_8(v__k, [8, [15, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_8(v__k, [9, [16, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_8(v__k, [10, [21, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_8 = (v_io) => {
    return v__cps__df_andThenIO_8(v_io, [62]);
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 60: {
            return v__x;
          }
          case 61: {
            const v__pk_61 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_61;
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
            return v__apply__df_andThenIO_4(v__k, v__lift_1(v__lam_28(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_4(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 61, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_4(v__k, [8, [14, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_4(v__k, [9, [20, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_4(v__k, [10, [25, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_4 = (v_io) => {
    return v__cps__df_andThenIO_4(v_io, [60]);
  };

  const v__apply__df_andThenIO_16 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 66: {
            return v__x;
          }
          case 67: {
            const v__pk_67 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_67;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_16 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_16(v__k, v__lift_1(v__lam_31(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_16(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 67, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_16(v__k, [8, [13, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_16(v__k, [9, [18, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_16(v__k, [10, [23, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_16 = (v_io) => {
    return v__cps__df_andThenIO_16(v_io, [66]);
  };

  const v__apply__df_andThenIO_12 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 64: {
            return v__x;
          }
          case 65: {
            const v__pk_65 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_65;
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
            return v__apply__df_andThenIO_12(v__k, v__lift_1(v__lam_30(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_12(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 65, v_io[1] = v__k, v_io[2] = v_s, v_io);
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
            return v__apply__df_andThenIO_12(v__k, [9, [17, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_12(v__k, [10, [22, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_12 = (v_io) => {
    return v__cps__df_andThenIO_12(v_io, [64]);
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 58: {
            return v__x;
          }
          case 59: {
            const v__pk_59 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_59;
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
            return v__apply__df_andThenIO_0(v__k, v__lift_1(v__lam_23(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_0(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 59, v_io[1] = v__k, v_io[2] = v_s, v_io);
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
            return v__apply__df_andThenIO_0(v__k, [9, [19, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_0(v__k, [10, [24, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_0 = (v_io) => {
    return v__cps__df_andThenIO_0(v_io, [58]);
  };

  const main = v__df_andThenIO_0(
    v__df_andThenIO_4(
      v__df_andThenIO_8(
        v__df_andThenIO_12(
          v__df_andThenIO_16(
            v__lift_24([7, String(v_extract(v_gAsc(0 | 0))), [5, [0]]])
          )
        )
      )
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
