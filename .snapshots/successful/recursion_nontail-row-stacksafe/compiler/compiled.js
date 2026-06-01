"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [16]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [3, [882564211, [17]]]; if (s < -2147483648) return [3, [3768445577, [16]]]; return [4, s|0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ const args = process.argv.slice(2); let list = [12]; for (let i = args.length - 1; i >= 0; i--) { const v = __entryArgEither(args[i]); if (v[0] !== 4) return v; list = [13, v[1], list]; } return [4, list]; }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

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
                const __t1 = [13, [2711245919, (1|0)], v_acc];
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
          return [13, [1615808600, "s"], v_acc];
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
                const __t1 = [13, [2711245919, (1|0)], v_acc];
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

const v__cps__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 26: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
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
              case 23: {
                const v__cap23_0 = __s[1];
                const __t0 = (v__args[0] = 36, v__args[1] = v__cap23_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 24: {
                const v__cap24_0 = __s[1];
                const __t0 = (v__args[0] = 37, v__args[1] = v__cap24_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 25: {
                const v__cap25_0 = __s[1];
                const __t0 = (v__args[0] = 38, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 27: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [58, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 28: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [59, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 29: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [60, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 30: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [61, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 31: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [62, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 32: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [63, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 33: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [64, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 34: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [65, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 35: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [66, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 36: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [67, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 37: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [68, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 38: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 26, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [69, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3)(v__args, [57]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_4_1__df__lam_4_10__df__lam_4_4__df__lam_4_7__df__lam_5_11__df__lam_5_2__df__lam_5_5__df__lam_5_8__lift_17__lift_18__lift_2__lift_3)([26, v__cl, v__arg0]);
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

const v__apply_sumRow = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 39: {
          return v__x;
        }
        case 40: {
          const v__pk_40 = __s[1];
          const v_n = __s[2];
          {
            const __s = __addInt32(v_n, v__x);
            switch (__s[0]) {
              case 3: {
                const v__e = __s[1];
                const __t0 = v__pk_40;
                const __t1 = (0|0);
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                const __t0 = v__pk_40;
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
        case 12: {
          return (v__apply_sumRow)(v__k, (0|0));
        }
        case 13: {
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
                const __t1 = (v_xs[0] = 40, v_xs[1] = v__k, v_xs[2] = v_n, v_xs);
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
    return (v__cps_sumRow)(v_xs, [39]);
};

const v__apply_countRow = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 41: {
          return v__x;
        }
        case 42: {
          const v__pk_42 = __s[1];
          const __t0 = v__pk_42;
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
                const __t1 = [42, v__k];
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
    return (v__cps_countRow)(v_n, [41]);
};

const v__lam_15 = (v__u) => {
    return [7, String((v_extract)((v_countRow)((1000000|0)))), [5, [0]]];
};

const v__apply__lift_20 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 47: {
          return v__x;
        }
        case 48: {
          const v__pk_48 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_48;
          const __t1 = (v__k[0] = 13, v__k[1] = v___f0, v__k[2] = v__x, v__k);
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
        case 12: {
          return (v__apply__lift_20)(v__k, [12]);
        }
        case 13: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 48, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__lift_20 = (v___input) => {
    return (v__cps__lift_20)(v___input, [47]);
};

const v__apply__lift_16 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 45: {
          return v__x;
        }
        case 46: {
          const v__pk_46 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_46;
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
          const __t1 = (v___input[0] = 46, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [8, [22, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [9, [23, v___f0]]);
        }
      }
    }
  }
};

const v__lift_16 = (v___input) => {
    return (v__cps__lift_16)(v___input, [45]);
};

const v__lam_19 = (v__u) => {
    return (v__lift_16)([7, " ", [5, [0]]]);
};

const v__lam_21 = (v__u) => {
    return (v__lift_16)([7, String((v_sumRow)((v_buildMixed)((3|0), (v__lift_20)([12])))), [5, [0]]]);
};

const v__lam_22 = (v__u) => {
    return (v__lift_16)([7, " ", [5, [0]]]);
};

const v__apply__lift_1 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 43: {
          return v__x;
        }
        case 44: {
          const v__pk_44 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_44;
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
          const __t1 = (v___input[0] = 44, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [24, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [25, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [43]);
};

const v__apply__df_andThenIO_9 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 55: {
          return v__x;
        }
        case 56: {
          const v__pk_56 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_56;
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
          return (v__apply__df_andThenIO_9)(v__k, (v__lift_1)((v__lam_22)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_9)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 56, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_9)(v__k, [8, [15, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_9)(v__k, [9, [18, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_9 = (v_io) => {
    return (v__cps__df_andThenIO_9)(v_io, [55]);
};

const v__apply__df_andThenIO_6 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 53: {
          return v__x;
        }
        case 54: {
          const v__pk_54 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_54;
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
          return (v__apply__df_andThenIO_6)(v__k, (v__lift_1)((v__lam_21)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_6)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 54, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_6)(v__k, [8, [17, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_6)(v__k, [9, [21, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_6 = (v_io) => {
    return (v__cps__df_andThenIO_6)(v_io, [53]);
};

const v__apply__df_andThenIO_3 = (v__k, v__x) => {
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
          const __t1 = (v_io[0] = 52, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [8, [16, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [9, [20, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_3 = (v_io) => {
    return (v__cps__df_andThenIO_3)(v_io, [51]);
};

const v__apply__df_andThenIO_0 = (v__k, v__x) => {
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
          const __t1 = (v_io[0] = 50, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [8, [14, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [9, [19, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_0 = (v_io) => {
    return (v__cps__df_andThenIO_0)(v_io, [49]);
};

const main = (v__df_andThenIO_0)((v__df_andThenIO_3)((v__df_andThenIO_6)((v__df_andThenIO_9)((v__lift_16)([7, String((v_sumRow)((v_buildOnes)((1000000|0), (v__lift_20)([12])))), [5, [0]]])))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();