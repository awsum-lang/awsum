"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [17]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [3, [882564211, [18]]]; if (s < -2147483648) return [3, [3768445577, [17]]]; return [4, s|0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [19]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [20]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [20]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [20]]]; } return [4, arg]; }
function __getArgs(){ const args = process.argv.slice(2); let list = [13]; for (let i = args.length - 1; i >= 0; i--) { const v = __entryArgEither(args[i]); if (v[0] !== 4) return v; list = [14, v[1], list]; } return [4, list]; }
function __stdinReadAll(){ let s; try { s = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(require('fs').readFileSync(0)); } catch (e) { return [3, [3239958583, [21]]]; } if (s.length > 134217728) return [3, [589989748, [19]]]; return [4, s]; }
function __stdinReadAllBytes(){ const buf = require('fs').readFileSync(0); let list = [13]; for (let i = buf.length - 1; i >= 0; i--) { list = [14, buf[i], list]; } return list; }

const v_extract = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1615808600: {
          const v__s = __s[1];
          return (0|0);
        }
        case 2711245919: {
          const v_n = __s[1];
          return v_n;
        }
      }
    }
};

const v_buildOnes = (v_n, v_acc) => {
  while (true) {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return v_acc;
        }
        case 2: {
          {
            const __s = __predInt32(v_n);
            switch (__s[0]) {
              case 3: {
                const v__e = __s[1];
                return v_acc;
              }
              case 4: {
                const v_m = __s[1];
                const __t0 = v_m;
                const __t1 = [14, [2711245919, (1|0)], v_acc];
                v_n = __t0;
                v_acc = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v_buildMixed = (v_n, v_acc) => {
  while (true) {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return [14, [1615808600, "s"], v_acc];
        }
        case 2: {
          {
            const __s = __predInt32(v_n);
            switch (__s[0]) {
              case 3: {
                const v__e = __s[1];
                return v_acc;
              }
              case 4: {
                const v_m = __s[1];
                const __t0 = v_m;
                const __t1 = [14, [2711245919, (1|0)], v_acc];
                v_n = __t0;
                v_acc = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v__cps__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 33: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 15: {
                const v__cap15_0 = __s[1];
                const __t0 = (v__args[0] = 34, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 16: {
                const v__cap16_0 = __s[1];
                const __t0 = (v__args[0] = 35, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 17: {
                const v__cap17_0 = __s[1];
                const __t0 = (v__args[0] = 36, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 18: {
                const v__cap18_0 = __s[1];
                const __t0 = (v__args[0] = 37, v__args[1] = v__cap18_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 19: {
                const v__cap19_0 = __s[1];
                const __t0 = (v__args[0] = 38, v__args[1] = v__cap19_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 20: {
                const v__cap20_0 = __s[1];
                const __t0 = (v__args[0] = 39, v__args[1] = v__cap20_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 21: {
                const v__cap21_0 = __s[1];
                const __t0 = (v__args[0] = 40, v__args[1] = v__cap21_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 22: {
                const v__cap22_0 = __s[1];
                const __t0 = (v__args[0] = 41, v__args[1] = v__cap22_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 23: {
                const v__cap23_0 = __s[1];
                const __t0 = (v__args[0] = 42, v__args[1] = v__cap23_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 24: {
                const v__cap24_0 = __s[1];
                const __t0 = (v__args[0] = 43, v__args[1] = v__cap24_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 25: {
                const v__cap25_0 = __s[1];
                const __t0 = (v__args[0] = 44, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 26: {
                const v__cap26_0 = __s[1];
                const __t0 = (v__args[0] = 45, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 27: {
                const v__cap27_0 = __s[1];
                const __t0 = (v__args[0] = 46, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 28: {
                const v__cap28_0 = __s[1];
                const __t0 = (v__args[0] = 47, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 29: {
                const v__cap29_0 = __s[1];
                const __t0 = (v__args[0] = 48, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 30: {
                const v__cap30_0 = __s[1];
                const __t0 = (v__args[0] = 49, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 31: {
                const v__cap31_0 = __s[1];
                const __t0 = (v__args[0] = 50, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 32: {
                const v__cap32_0 = __s[1];
                const __t0 = (v__args[0] = 51, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 34: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [71, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 35: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [72, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 36: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [73, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 37: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [74, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 38: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [75, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 39: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [76, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 40: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [77, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 41: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [78, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 42: {
          const v_cont = __s[1];
          const v_bytes = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
          const __t1 = [79, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 43: {
          const v_cont = __s[1];
          const v_bytes = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
          const __t1 = [80, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 44: {
          const v_cont = __s[1];
          const v_bytes = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
          const __t1 = [81, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 45: {
          const v_cont = __s[1];
          const v_bytes = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
          const __t1 = [82, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 46: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [83, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 47: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [84, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 48: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [85, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 49: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [86, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 50: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [87, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 51: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 33, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [88, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4)(v__args, [70]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_5_1__df__lam_5_13__df__lam_5_5__df__lam_5_9__df__lam_6_10__df__lam_6_14__df__lam_6_2__df__lam_6_6__df__lam_7_11__df__lam_7_15__df__lam_7_3__df__lam_7_7__lift_2__lift_25__lift_26__lift_27__lift_3__lift_4)([33, v__cl, v__arg0]);
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
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = __t0;
          continue;
        }
        case 9: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __stdinReadAll());
          v_io = __t0;
          continue;
        }
        case 10: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __stdinReadAllBytes());
          v_io = __t0;
          continue;
        }
      }
    }
  }
};

const v__apply_sumRow = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 52: {
          return v__x;
        }
        case 53: {
          const v__pk_53 = __s[1];
          const v_n = __s[2];
          {
            const __s = __addInt32(v_n, v__x);
            switch (__s[0]) {
              case 3: {
                const v__e = __s[1];
                const __t0 = v__pk_53;
                const __t1 = (0|0);
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                const __t0 = v__pk_53;
                const __t1 = v_r;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v__cps_sumRow = (v_xs, v__k) => {
  while (true) {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 13: {
          return (v__apply_sumRow)(v__k, (0|0));
        }
        case 14: {
          const v_h = __s[1];
          const v_t = __s[2];
          {
            const __s = v_h;
            switch (__s[0]) {
              case 1615808600: {
                const v__s = __s[1];
                const __t0 = v_t;
                const __t1 = v__k;
                v_xs = __t0;
                v__k = __t1;
                continue;
              }
              case 2711245919: {
                const v_n = __s[1];
                const __t0 = v_t;
                const __t1 = (v_xs[0] = 53, v_xs[1] = v__k, v_xs[2] = v_n, v_xs);
                v_xs = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v_sumRow = (v_xs) => {
    return (v__cps_sumRow)(v_xs, [52]);
};

const v__apply_countRow = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 54: {
          return v__x;
        }
        case 55: {
          const v__pk_55 = __s[1];
          const __t0 = v__pk_55;
          const __t1 = [2711245919, (v_extract)(v__x)];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps_countRow = (v_n, v__k) => {
  while (true) {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return (v__apply_countRow)(v__k, [2711245919, v_n]);
        }
        case 2: {
          {
            const __s = __predInt32(v_n);
            switch (__s[0]) {
              case 3: {
                const v__e = __s[1];
                return (v__apply_countRow)(v__k, [2711245919, v_n]);
              }
              case 4: {
                const v_m = __s[1];
                const __t0 = v_m;
                const __t1 = [55, v__k];
                v_n = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v_countRow = (v_n) => {
    return (v__cps_countRow)(v_n, [54]);
};

const v__lam_23 = (v__u) => {
    return [7, String((v_extract)((v_countRow)((1000000|0)))), [5, [0]]];
};

const v__apply__lift_29 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 60: {
          return v__x;
        }
        case 61: {
          const v__pk_61 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_61;
          const __t1 = (v__k[0] = 14, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_29 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 13: {
          return (v__apply__lift_29)(v__k, [13]);
        }
        case 14: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 61, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__lift_29 = (v___input) => {
    return (v__cps__lift_29)(v___input, [60]);
};

const v__apply__lift_24 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 58: {
          return v__x;
        }
        case 59: {
          const v__pk_59 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_59;
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
          return (v__apply__lift_24)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_24)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 59, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_24)(v__k, [8, [28, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_24)(v__k, [9, [29, v___f0]]);
        }
        case 10: {
          const v___f0 = __s[1];
          return (v__apply__lift_24)(v__k, [10, [30, v___f0]]);
        }
      }
    }
  }
};

const v__lift_24 = (v___input) => {
    return (v__cps__lift_24)(v___input, [58]);
};

const v__lam_28 = (v__u) => {
    return (v__lift_24)([7, " ", [5, [0]]]);
};

const v__lam_30 = (v__u) => {
    return (v__lift_24)([7, String((v_sumRow)((v_buildMixed)((3|0), (v__lift_29)([13])))), [5, [0]]]);
};

const v__lam_31 = (v__u) => {
    return (v__lift_24)([7, " ", [5, [0]]]);
};

const v__apply__lift_1 = (v__k, v__x) => {
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

const v__cps__lift_1 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [6, v___f0]);
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
          return (v__apply__lift_1)(v__k, [8, [27, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [31, v___f0]]);
        }
        case 10: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [10, [32, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [56]);
};

const v__apply__df_andThenIO_8 = (v__k, v__x) => {
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

const v__cps__df_andThenIO_8 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_8)(v__k, (v__lift_1)((v__lam_30)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_8)(v__k, [6, v_e]);
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
          return (v__apply__df_andThenIO_8)(v__k, [8, [18, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_8)(v__k, [9, [19, v_cont]]);
        }
        case 10: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_8)(v__k, [10, [23, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_8 = (v_io) => {
    return (v__cps__df_andThenIO_8)(v_io, [66]);
};

const v__apply__df_andThenIO_4 = (v__k, v__x) => {
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

const v__cps__df_andThenIO_4 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_4)(v__k, (v__lift_1)((v__lam_28)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_4)(v__k, [6, v_e]);
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
          return (v__apply__df_andThenIO_4)(v__k, [8, [17, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_4)(v__k, [9, [22, v_cont]]);
        }
        case 10: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_4)(v__k, [10, [26, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_4 = (v_io) => {
    return (v__cps__df_andThenIO_4)(v_io, [64]);
};

const v__apply__df_andThenIO_12 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 68: {
          return v__x;
        }
        case 69: {
          const v__pk_69 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_69;
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
          return (v__apply__df_andThenIO_12)(v__k, (v__lift_1)((v__lam_31)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_12)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 69, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_12)(v__k, [8, [16, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_12)(v__k, [9, [20, v_cont]]);
        }
        case 10: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_12)(v__k, [10, [24, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_12 = (v_io) => {
    return (v__cps__df_andThenIO_12)(v_io, [68]);
};

const v__apply__df_andThenIO_0 = (v__k, v__x) => {
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

const v__cps__df_andThenIO_0 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, (v__lift_1)((v__lam_23)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [6, v_e]);
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
          return (v__apply__df_andThenIO_0)(v__k, [8, [15, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [9, [21, v_cont]]);
        }
        case 10: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [10, [25, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_0 = (v_io) => {
    return (v__cps__df_andThenIO_0)(v_io, [62]);
};

const main = (v__df_andThenIO_0)((v__df_andThenIO_4)((v__df_andThenIO_8)((v__df_andThenIO_12)((v__lift_24)([7, String((v_sumRow)((v_buildOnes)((1000000|0), (v__lift_29)([13])))), [5, [0]]])))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();