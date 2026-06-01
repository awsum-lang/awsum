"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ const args = process.argv.slice(2); let list = [12]; for (let i = args.length - 1; i >= 0; i--) { const v = __entryArgEither(args[i]); if (v[0] !== 4) return v; list = [13, v[1], list]; } return [4, list]; }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

const v_toRowB = (v__s) => {
    return [2269767818, [26]];
};

const v_toRowA = (v__s) => {
    return [2252990199, [25]];
};

const v_remap = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3640903312: {
          const v__y = __s[1];
          return [2269767818, [26]];
        }
        case 3657680931: {
          const v__x = __s[1];
          return [2252990199, [25]];
        }
      }
    }
};

const v_pureIO = (v_x) => {
    return [5, v_x];
};

const v_okSrc = (v_pureIO)((5|0));

const v_handlerABC = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 2252990199: {
          const v__a = __s[1];
          return [7, "ErrA", [5, [0]]];
        }
        case 2269767818: {
          const v__b = __s[1];
          return [7, "ErrB", [5, [0]]];
        }
      }
    }
};

const v_handlerAB = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 2252990199: {
          const v__a = __s[1];
          return [7, "ErrA", [5, [0]]];
        }
        case 2269767818: {
          const v__b = __s[1];
          return [7, "ErrB", [5, [0]]];
        }
      }
    }
};

const v_failIO = (v_e) => {
    return [6, v_e];
};

const v_failSrc = (v_failIO)([22]);

const v_failX = (v_failIO)([3657680931, [23]]);

const v_failY = (v_failIO)([3640903312, [24]]);

const v__lam_35 = (v__u) => {
    return [7, "=", [5, [0]]];
};

const v__lam_34 = (v_act, v__u) => {
    return v_act;
};

const v__lam_33 = (v__u) => {
    return [7, "\n", [5, [0]]];
};

const v__cps__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 69: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 27: {
                const v__cap27_0 = __s[1];
                const __t0 = (v__args[0] = 70, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 28: {
                const v__cap28_0 = __s[1];
                const __t0 = (v__args[0] = 71, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 29: {
                const v__cap29_0 = __s[1];
                const __t0 = (v__args[0] = 72, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 30: {
                const v__cap30_0 = __s[1];
                const __t0 = (v__args[0] = 73, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 31: {
                const v__cap31_0 = __s[1];
                const __t0 = (v__args[0] = 74, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 32: {
                const v__cap32_0 = __s[1];
                const __t0 = (v__args[0] = 75, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 33: {
                const v__cap33_0 = __s[1];
                const __t0 = (v__args[0] = 76, v__args[1] = v__cap33_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 34: {
                const v__cap34_0 = __s[1];
                const __t0 = (v__args[0] = 77, v__args[1] = v__cap34_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 35: {
                const v__cap35_0 = __s[1];
                const __t0 = (v__args[0] = 78, v__args[1] = v__cap35_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 36: {
                const v__cap36_0 = __s[1];
                const v__cap36_1 = __s[2];
                const __t0 = [79, v__cap36_0, v__cap36_1, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 37: {
                const v__cap37_0 = __s[1];
                const __t0 = (v__args[0] = 80, v__args[1] = v__cap37_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 38: {
                const v__cap38_0 = __s[1];
                const __t0 = (v__args[0] = 81, v__args[1] = v__cap38_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 39: {
                const v__cap39_0 = __s[1];
                const __t0 = (v__args[0] = 82, v__args[1] = v__cap39_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 40: {
                const v__cap40_0 = __s[1];
                const __t0 = (v__args[0] = 83, v__args[1] = v__cap40_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 41: {
                const v__cap41_0 = __s[1];
                const __t0 = (v__args[0] = 84, v__args[1] = v__cap41_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 42: {
                const v__cap42_0 = __s[1];
                const __t0 = (v__args[0] = 85, v__args[1] = v__cap42_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 43: {
                const v__cap43_0 = __s[1];
                const v__cap43_1 = __s[2];
                const __t0 = [86, v__cap43_0, v__cap43_1, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 44: {
                const v__cap44_0 = __s[1];
                const __t0 = (v__args[0] = 87, v__args[1] = v__cap44_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 45: {
                const v__cap45_0 = __s[1];
                const __t0 = (v__args[0] = 88, v__args[1] = v__cap45_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 46: {
                const v__cap46_0 = __s[1];
                const __t0 = (v__args[0] = 89, v__args[1] = v__cap46_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 47: {
                const v__cap47_0 = __s[1];
                const __t0 = (v__args[0] = 90, v__args[1] = v__cap47_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 48: {
                const v__cap48_0 = __s[1];
                const __t0 = (v__args[0] = 91, v__args[1] = v__cap48_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 49: {
                const v__cap49_0 = __s[1];
                const __t0 = (v__args[0] = 92, v__args[1] = v__cap49_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 50: {
                const v__cap50_0 = __s[1];
                const __t0 = (v__args[0] = 93, v__args[1] = v__cap50_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 51: {
                const v__cap51_0 = __s[1];
                const __t0 = (v__args[0] = 94, v__args[1] = v__cap51_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 52: {
                const v__cap52_0 = __s[1];
                const __t0 = (v__args[0] = 95, v__args[1] = v__cap52_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 53: {
                const v__cap53_0 = __s[1];
                const __t0 = (v__args[0] = 96, v__args[1] = v__cap53_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 54: {
                const v__cap54_0 = __s[1];
                const __t0 = (v__args[0] = 97, v__args[1] = v__cap54_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 55: {
                const v__cap55_0 = __s[1];
                const __t0 = (v__args[0] = 98, v__args[1] = v__cap55_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 56: {
                const v__cap56_0 = __s[1];
                const __t0 = (v__args[0] = 99, v__args[1] = v__cap56_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 57: {
                const v__cap57_0 = __s[1];
                const __t0 = (v__args[0] = 100, v__args[1] = v__cap57_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 58: {
                const v__cap58_0 = __s[1];
                const __t0 = (v__args[0] = 101, v__args[1] = v__cap58_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 59: {
                const v__cap59_0 = __s[1];
                const __t0 = (v__args[0] = 102, v__args[1] = v__cap59_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 62: {
                const v__cap62_0 = __s[1];
                const __t0 = (v__args[0] = 105, v__args[1] = v__cap62_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 63: {
                const v__cap63_0 = __s[1];
                const __t0 = (v__args[0] = 106, v__args[1] = v__cap63_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 64: {
                const v__cap64_0 = __s[1];
                const __t0 = (v__args[0] = 107, v__args[1] = v__cap64_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 65: {
                const v__cap65_0 = __s[1];
                const __t0 = (v__args[0] = 108, v__args[1] = v__cap65_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 66: {
                const v__cap66_0 = __s[1];
                const __t0 = (v__args[0] = 109, v__args[1] = v__cap66_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 67: {
                const v__cap67_0 = __s[1];
                const __t0 = (v__args[0] = 110, v__args[1] = v__cap67_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 68: {
                const v__cap68_0 = __s[1];
                const __t0 = (v__args[0] = 111, v__args[1] = v__cap68_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 70: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [155, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 71: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [156, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 72: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [157, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 73: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [158, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 74: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [159, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 75: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [160, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 76: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [161, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 77: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [162, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 78: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [163, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 79: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const v__df__lam_4_28_cap1_0 = __s[3];
          const __t0 = [69, v_cont, v_result];
          const __t1 = [164, v__k, v__df__lam_4_28_cap1_0];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 80: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [165, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 81: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [166, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 82: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [167, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 83: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [168, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 84: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [169, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 85: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [170, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 86: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const v__df__lam_5_29_cap1_0 = __s[3];
          const __t0 = [69, v_cont, v_result];
          const __t1 = [171, v__k, v__df__lam_5_29_cap1_0];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 87: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [172, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 88: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [173, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 89: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [174, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 90: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [175, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 91: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [176, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 92: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [177, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 93: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [178, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 94: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [179, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 95: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [180, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 96: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [181, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 97: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [182, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 98: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [183, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 99: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [184, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 100: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [185, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 101: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [186, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 102: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [187, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 105: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [190, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 106: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [191, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 107: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [192, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 108: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [193, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 109: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [194, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 110: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [195, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 111: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 69, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [196, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38)(v__args, [154]);
};

const v__bi_showInt32 = (v__x0) => {
    return String(v__x0);
};

const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38)([69, v__cl, v__arg0]);
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

const v__apply__lift_36 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 122: {
          return v__x;
        }
        case 123: {
          const v__pk_123 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_123;
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
          return (v__apply__lift_36)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_36)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 123, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_36)(v__k, [8, [67, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_36)(v__k, [9, [68, v___f0]]);
        }
      }
    }
  }
};

const v__lift_36 = (v___input) => {
    return (v__cps__lift_36)(v___input, [122]);
};

const v__apply__lift_28 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 120: {
          return v__x;
        }
        case 121: {
          const v__pk_121 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_121;
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
          return (v__apply__lift_28)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_28)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 121, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_28)(v__k, [8, [64, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_28)(v__k, [9, [66, v___f0]]);
        }
      }
    }
  }
};

const v__lift_28 = (v___input) => {
    return (v__cps__lift_28)(v___input, [120]);
};

const v__apply__lift_25 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 118: {
          return v__x;
        }
        case 119: {
          const v__pk_119 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_119;
          const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_25 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_25)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_25)(v__k, [6, [3801428867, v___f0]]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 119, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_25)(v__k, [8, [62, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_25)(v__k, [9, [63, v___f0]]);
        }
      }
    }
  }
};

const v__lift_25 = (v___input) => {
    return (v__cps__lift_25)(v___input, [118]);
};

const v__apply__lift_16 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 114: {
          return v__x;
        }
        case 115: {
          const v__pk_115 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_115;
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
          return (v__apply__lift_16)(v__k, [6, [3801428867, v___f0]]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 115, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [8, [57, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [9, [58, v___f0]]);
        }
      }
    }
  }
};

const v__lift_16 = (v___input) => {
    return (v__cps__lift_16)(v___input, [114]);
};

const v__apply__lift_1 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 112: {
          return v__x;
        }
        case 113: {
          const v__pk_113 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_113;
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
          const __t1 = (v___input[0] = 113, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [59, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [65, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [112]);
};

const v__apply__df_mapIOError_6 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 128: {
          return v__x;
        }
        case 129: {
          const v__pk_129 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_129;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_mapIOError_6 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_mapIOError_6)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_mapIOError_6)(v__k, [6, (v_remap)(v_e)]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 129, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_mapIOError_6)(v__k, [8, [53, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_mapIOError_6)(v__k, [9, [56, v_cont]]);
        }
      }
    }
  }
};

const v__df_mapIOError_6 = (v_io) => {
    return (v__cps__df_mapIOError_6)(v_io, [128]);
};

const v_remappedX = (v__df_mapIOError_6)(v_failX);

const v_remappedY = (v__df_mapIOError_6)(v_failY);

const v__apply__df_mapIOError_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 126: {
          return v__x;
        }
        case 127: {
          const v__pk_127 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_127;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_mapIOError_3 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_mapIOError_3)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_mapIOError_3)(v__k, [6, (v_toRowB)(v_e)]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 127, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_mapIOError_3)(v__k, [8, [52, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_mapIOError_3)(v__k, [9, [55, v_cont]]);
        }
      }
    }
  }
};

const v__df_mapIOError_3 = (v_io) => {
    return (v__cps__df_mapIOError_3)(v_io, [126]);
};

const v_mappedB = (v__df_mapIOError_3)(v_failSrc);

const v__apply__df_mapIOError_0 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 124: {
          return v__x;
        }
        case 125: {
          const v__pk_125 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_125;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_mapIOError_0 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_mapIOError_0)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_mapIOError_0)(v__k, [6, (v_toRowA)(v_e)]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 125, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_mapIOError_0)(v__k, [8, [51, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_mapIOError_0)(v__k, [9, [54, v_cont]]);
        }
      }
    }
  }
};

const v__df_mapIOError_0 = (v_io) => {
    return (v__cps__df_mapIOError_0)(v_io, [124]);
};

const v_mappedA = (v__df_mapIOError_0)(v_failSrc);

const v_mappedOk = (v__df_mapIOError_0)(v_okSrc);

const v__apply__df_mapIO_15 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 134: {
          return v__x;
        }
        case 135: {
          const v__pk_135 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_135;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_mapIO_15 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_mapIO_15)(v__k, [5, (v__bi_showInt32)(v_a)]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_mapIO_15)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 135, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_mapIO_15)(v__k, [8, [49, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_mapIO_15)(v__k, [9, [50, v_cont]]);
        }
      }
    }
  }
};

const v__df_mapIO_15 = (v_io) => {
    return (v__cps__df_mapIO_15)(v_io, [134]);
};

const v__apply__df_handleErrorIO_9 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 130: {
          return v__x;
        }
        case 131: {
          const v__pk_131 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_131;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_handleErrorIO_9 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_9)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_9)(v__k, (v_handlerAB)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 131, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_9)(v__k, [8, [27, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_9)(v__k, [9, [29, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_9 = (v_io) => {
    return (v__cps__df_handleErrorIO_9)(v_io, [130]);
};

const v__apply__df_handleErrorIO_18 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 136: {
          return v__x;
        }
        case 137: {
          const v__pk_137 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_137;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_handleErrorIO_18 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_18)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_18)(v__k, (v_handlerABC)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 137, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_18)(v__k, [8, [28, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_18)(v__k, [9, [30, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_18 = (v_io) => {
    return (v__cps__df_handleErrorIO_18)(v_io, [136]);
};

const v__apply__df_andThenIO_42 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 152: {
          return v__x;
        }
        case 153: {
          const v__pk_153 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_153;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__apply__df_andThenIO_39 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 150: {
          return v__x;
        }
        case 151: {
          const v__pk_151 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_151;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__apply__df_andThenIO_36 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 148: {
          return v__x;
        }
        case 149: {
          const v__pk_149 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_149;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__apply__df_andThenIO_33 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 146: {
          return v__x;
        }
        case 147: {
          const v__pk_147 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_147;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__apply__df_andThenIO_30 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 144: {
          return v__x;
        }
        case 145: {
          const v__pk_145 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_145;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_andThenIO_30 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_30)(v__k, (v__lift_1)((v__lam_35)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_30)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 145, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_30)(v__k, [8, [37, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_30)(v__k, [9, [44, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_30 = (v_io) => {
    return (v__cps__df_andThenIO_30)(v_io, [144]);
};

const v__apply__df_andThenIO_27 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 142: {
          return v__x;
        }
        case 143: {
          const v__pk_143 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_143;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_andThenIO_27 = (v_io, v__df_andThenIO_27_cap0_0, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_27)(v__k, (v__lift_1)((v__lam_34)(v__df_andThenIO_27_cap0_0, v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_27)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = v__df_andThenIO_27_cap0_0;
          const __t2 = (v_io[0] = 143, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__df_andThenIO_27_cap0_0 = __t1;
          v__k = __t2;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_27)(v__k, [8, [36, v_cont, v__df_andThenIO_27_cap0_0]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_27)(v__k, [9, [43, v_cont, v__df_andThenIO_27_cap0_0]]);
        }
      }
    }
  }
};

const v__df_andThenIO_27 = (v_io, v__df_andThenIO_27_cap0_0) => {
    return (v__cps__df_andThenIO_27)(v_io, v__df_andThenIO_27_cap0_0, [142]);
};

const v__apply__df_andThenIO_24 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 140: {
          return v__x;
        }
        case 141: {
          const v__pk_141 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_141;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df_andThenIO_24 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_24)(v__k, (v__lift_1)((v__lam_33)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_24)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 141, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_24)(v__k, [8, [35, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_24)(v__k, [9, [42, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_24 = (v_io) => {
    return (v__cps__df_andThenIO_24)(v_io, [140]);
};

const v_line = (v_label, v_act) => {
    return (v__df_andThenIO_24)((v__df_andThenIO_27)((v__df_andThenIO_30)((v__lift_36)([7, v_label, [5, [0]]])), v_act));
};

const v__apply__df__rowspec_24_21 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 138: {
          return v__x;
        }
        case 139: {
          const v__pk_139 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_139;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df__rowspec_24_21 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df__rowspec_24_21)(v__k, (v__lift_25)((v__bi_IO_Stdout_print)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df__rowspec_24_21)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 139, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_24_21)(v__k, [8, [33, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_24_21)(v__k, [9, [34, v_cont]]);
        }
      }
    }
  }
};

const v__df__rowspec_24_21 = (v_io) => {
    return (v__cps__df__rowspec_24_21)(v_io, [138]);
};

const v_observeABC = (v_io) => {
    return (v__df_handleErrorIO_18)((v__df__rowspec_24_21)((v__lift_28)((v__df_mapIO_15)(v_io))));
};

const v__lam_39 = (v__u) => {
    return (v_line)("remappedY", (v_observeABC)(v_remappedY));
};

const v__cps__df_andThenIO_33 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_33)(v__k, (v__lift_1)((v__lam_39)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_33)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 147, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_33)(v__k, [8, [38, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_33)(v__k, [9, [45, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_33 = (v_io) => {
    return (v__cps__df_andThenIO_33)(v_io, [146]);
};

const v__lam_40 = (v__u) => {
    return (v__lift_36)((v_line)("remappedX", (v_observeABC)(v_remappedX)));
};

const v__cps__df_andThenIO_36 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_36)(v__k, (v__lift_1)((v__lam_40)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_36)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 149, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_36)(v__k, [8, [39, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_36)(v__k, [9, [46, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_36 = (v_io) => {
    return (v__cps__df_andThenIO_36)(v_io, [148]);
};

const v__apply__df__rowspec_15_12 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 132: {
          return v__x;
        }
        case 133: {
          const v__pk_133 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_133;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df__rowspec_15_12 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df__rowspec_15_12)(v__k, (v__lift_16)((v__bi_IO_Stdout_print)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df__rowspec_15_12)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 133, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_15_12)(v__k, [8, [31, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_15_12)(v__k, [9, [32, v_cont]]);
        }
      }
    }
  }
};

const v__df__rowspec_15_12 = (v_io) => {
    return (v__cps__df__rowspec_15_12)(v_io, [132]);
};

const v_observeAB = (v_io) => {
    return (v__df_handleErrorIO_9)((v__df__rowspec_15_12)((v__df_mapIO_15)(v_io)));
};

const v__lam_41 = (v__u) => {
    return (v__lift_36)((v_line)("mappedOk", (v_observeAB)(v_mappedOk)));
};

const v__cps__df_andThenIO_39 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_39)(v__k, (v__lift_1)((v__lam_41)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_39)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 151, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_39)(v__k, [8, [40, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_39)(v__k, [9, [47, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_39 = (v_io) => {
    return (v__cps__df_andThenIO_39)(v_io, [150]);
};

const v__lam_42 = (v__u) => {
    return (v__lift_36)((v_line)("mappedB", (v_observeAB)(v_mappedB)));
};

const v__cps__df_andThenIO_42 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_42)(v__k, (v__lift_1)((v__lam_42)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_42)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 153, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_42)(v__k, [8, [41, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_42)(v__k, [9, [48, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_42 = (v_io) => {
    return (v__cps__df_andThenIO_42)(v_io, [152]);
};

const main = (v__df_andThenIO_33)((v__df_andThenIO_36)((v__df_andThenIO_39)((v__df_andThenIO_42)((v__lift_36)((v_line)("mappedA", (v_observeAB)(v_mappedA)))))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();