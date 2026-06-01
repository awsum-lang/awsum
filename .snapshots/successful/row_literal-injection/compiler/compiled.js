"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ const args = process.argv.slice(2); let list = [12]; for (let i = args.length - 1; i >= 0; i--) { const v = __entryArgEither(args[i]); if (v[0] !== 4) return v; list = [13, v[1], list]; } return [4, list]; }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

const v_gU = (v_n) => {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return [3538687084, (11 >>> 0)];
        }
        case 2: {
          return [3538687084, (13 >>> 0)];
        }
      }
    }
};

const v_gBare = (v_n) => {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return [2711245919, (7|0)];
        }
        case 2: {
          return [2711245919, (9|0)];
        }
      }
    }
};

const v_gAsc = (v_n) => {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return [2711245919, (7|0)];
        }
        case 2: {
          return [2711245919, (9|0)];
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

const v__lam_15 = (v__u) => {
    return [7, String((v_extractU)((v_gU)((1|0)))), [5, [0]]];
};

const v__cps__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_13__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_14__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 24: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 10: {
                const v__cap10_0 = __s[1];
                const __t0 = (v__args[0] = 25, v__args[1] = v__cap10_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 11: {
                const v__cap11_0 = __s[1];
                const __t0 = (v__args[0] = 26, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 12: {
                const v__cap12_0 = __s[1];
                const __t0 = (v__args[0] = 27, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 13: {
                const v__cap13_0 = __s[1];
                const __t0 = (v__args[0] = 28, v__args[1] = v__cap13_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 14: {
                const v__cap14_0 = __s[1];
                const __t0 = (v__args[0] = 29, v__args[1] = v__cap14_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 15: {
                const v__cap15_0 = __s[1];
                const __t0 = (v__args[0] = 30, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 16: {
                const v__cap16_0 = __s[1];
                const __t0 = (v__args[0] = 31, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 17: {
                const v__cap17_0 = __s[1];
                const __t0 = (v__args[0] = 32, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 18: {
                const v__cap18_0 = __s[1];
                const __t0 = (v__args[0] = 33, v__args[1] = v__cap18_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 19: {
                const v__cap19_0 = __s[1];
                const __t0 = (v__args[0] = 34, v__args[1] = v__cap19_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 20: {
                const v__cap20_0 = __s[1];
                const __t0 = (v__args[0] = 35, v__args[1] = v__cap20_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 21: {
                const v__cap21_0 = __s[1];
                const __t0 = (v__args[0] = 36, v__args[1] = v__cap21_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 22: {
                const v__cap22_0 = __s[1];
                const __t0 = (v__args[0] = 37, v__args[1] = v__cap22_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 23: {
                const v__cap23_0 = __s[1];
                const __t0 = (v__args[0] = 38, v__args[1] = v__cap23_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 25: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [54, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 26: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [55, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 27: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [56, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 28: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [57, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 29: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [58, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 30: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [59, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 31: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [60, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 32: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [61, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 33: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [62, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 34: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [63, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 35: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [64, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 36: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [65, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 37: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [66, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 38: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 24, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [67, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_13__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_14__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_13__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_14__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3)(v__args, [53]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_13__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_14__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3)([24, v__cl, v__arg0]);
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
      }
    }
  }
};

const v__apply__lift_16 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 41: {
          return v__x;
        }
        case 42: {
          const v__pk_42 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_42;
          const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_16 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 42, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [8, [20, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [9, [21, v___f0]]);
        }
      }
    }
  }
};

const v__lift_16 = (v___input) => {
    return (v__cps__lift_16)(v___input, [41]);
};

const v__lam_19 = (v__u) => {
    return (v__lift_16)([7, String((v_extractU)((v_gU)((0|0)))), [5, [0]]]);
};

const v__lam_20 = (v__u) => {
    return (v__lift_16)([7, String((v_extract)((v_gBare)((1|0)))), [5, [0]]]);
};

const v__lam_21 = (v__u) => {
    return (v__lift_16)([7, String((v_extract)((v_gBare)((0|0)))), [5, [0]]]);
};

const v__lam_22 = (v__u) => {
    return (v__lift_16)([7, String((v_extract)((v_gAsc)((1|0)))), [5, [0]]]);
};

const v__apply__lift_1 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 39: {
          return v__x;
        }
        case 40: {
          const v__pk_40 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_40;
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
          const __t1 = (v___input[0] = 40, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [22, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [23, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [39]);
};

const v__apply__df_andThenIO_9 = (v__k, v__x) => {
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

const v__cps__df_andThenIO_9 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_9)(v__k, (v__lift_1)((v__lam_21)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_9)(v__k, [6, v_e]);
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
          return (v__apply__df_andThenIO_9)(v__k, [8, [11, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_9)(v__k, [9, [15, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_9 = (v_io) => {
    return (v__cps__df_andThenIO_9)(v_io, [49]);
};

const v__apply__df_andThenIO_6 = (v__k, v__x) => {
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

const v__cps__df_andThenIO_6 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_6)(v__k, (v__lift_1)((v__lam_20)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_6)(v__k, [6, v_e]);
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
          return (v__apply__df_andThenIO_6)(v__k, [8, [14, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_6)(v__k, [9, [19, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_6 = (v_io) => {
    return (v__cps__df_andThenIO_6)(v_io, [47]);
};

const v__apply__df_andThenIO_3 = (v__k, v__x) => {
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

const v__cps__df_andThenIO_3 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, (v__lift_1)((v__lam_19)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [6, v_e]);
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
          return (v__apply__df_andThenIO_3)(v__k, [8, [13, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [9, [18, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_3 = (v_io) => {
    return (v__cps__df_andThenIO_3)(v_io, [45]);
};

const v__apply__df_andThenIO_12 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 51: {
          return v__x;
        }
        case 52: {
          const v__pk_52 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_52;
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
          return (v__apply__df_andThenIO_12)(v__k, (v__lift_1)((v__lam_22)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_12)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 52, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_12)(v__k, [8, [12, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_12)(v__k, [9, [16, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_12 = (v_io) => {
    return (v__cps__df_andThenIO_12)(v_io, [51]);
};

const v__apply__df_andThenIO_0 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 43: {
          return v__x;
        }
        case 44: {
          const v__pk_44 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_44;
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
          return (v__apply__df_andThenIO_0)(v__k, (v__lift_1)((v__lam_15)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 44, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [8, [10, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [9, [17, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_0 = (v_io) => {
    return (v__cps__df_andThenIO_0)(v_io, [43]);
};

const main = (v__df_andThenIO_0)((v__df_andThenIO_3)((v__df_andThenIO_6)((v__df_andThenIO_9)((v__df_andThenIO_12)((v__lift_16)([7, String((v_extract)((v_gAsc)((0|0)))), [5, [0]]]))))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();