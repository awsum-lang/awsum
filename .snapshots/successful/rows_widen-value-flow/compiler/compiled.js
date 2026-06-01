"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ const args = process.argv.slice(2); let list = [12]; for (let i = args.length - 1; i >= 0; i--) { const v = __entryArgEither(args[i]); if (v[0] !== 4) return v; list = [13, v[1], list]; } return [4, list]; }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

const v_vStr = [3, "strErr"];

const v_vSecond = [3, [25]];

const v_vOkA = [4, (7|0)];

const v_vFirst = [3, [24]];

const v_vErrB = [3, [23]];

const v_vErrA = [3, [22]];

const v_tagged = (v_label, v_val) => {
    {
      const __s = __concat(v_label, "=");
      switch (__s[0]) {
        case 3: {
          const v__do_e_1 = __s[1];
          return [3, v__do_e_1];
        }
        case 4: {
          const v_a = __s[1];
          {
            const __s = __concat(v_a, v_val);
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                return [3, v__do_e_0];
              }
              case 4: {
                const v_b = __s[1];
                return __concat(v_b, "\n");
              }
            }
          }
        }
      }
    }
};

const v_showTwoA = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 925038822: {
                const v_t = __s[1];
                {
                  const __s = v_t;
                  switch (__s[0]) {
                    case 24: {
                      return "First";
                    }
                    case 25: {
                      return "Second";
                    }
                  }
                }
              }
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
};

const v_showStrA = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 1615808600: {
                const v_s = __s[1];
                return v_s;
              }
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
};

const v_showAB = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
              case 2269767818: {
                const v__b = __s[1];
                return "ErrB";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
};

const v_pureIO = (v_x) => {
    return [5, v_x];
};

const v_printErr = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 18: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
};

const v_failIO = (v_e) => {
    return [6, v_e];
};

const v_appendTagged = (v_acc, v_label, v_val) => {
    {
      const __s = (v_tagged)(v_label, v_val);
      switch (__s[0]) {
        case 3: {
          const v__do_e_2 = __s[1];
          return [3, v__do_e_2];
        }
        case 4: {
          const v_line = __s[1];
          return __concat(v_acc, v_line);
        }
      }
    }
};

const v__lift_21 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 10: {
          return [10];
        }
        case 11: {
          const v___f0 = __s[1];
          return [11, v___f0];
        }
      }
    }
};

const v__lift_20 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [1615808600, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
};

const v_strWiden = (v__lift_20)(v_vStr);

const v__lift_19 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2252990199, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
};

const v__lift_18 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [925038822, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
};

const v_nestedUnion = (v_m) => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 10: {
          return (v__lift_18)(v_vFirst);
        }
        case 11: {
          const v_b = __s[1];
          {
            const __s = v_b;
            switch (__s[0]) {
              case 1: {
                return (v__lift_19)(v_vErrA);
              }
              case 2: {
                return (v__lift_18)(v_vSecond);
              }
            }
          }
        }
      }
    }
};

const v__lift_16 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2269767818, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
};

const v__lift_15 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2252990199, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
};

const v_caseUnion = (v_flag) => {
    {
      const __s = v_flag;
      switch (__s[0]) {
        case 1: {
          return (v__lift_15)(v_vErrA);
        }
        case 2: {
          return (v__lift_16)(v_vErrB);
        }
      }
    }
};

const v_defBodyLeft = (v__lift_15)(v_vErrA);

const v_defBodyRight = (v__lift_15)(v_vOkA);

const v__let_17 = (v_x) => {
    return (v__lift_16)(v_x);
};

const v_letBody = (v__let_17)(v_vErrB);

const v_render = ((s) => { switch(s[0]) { case 3: { const v__do_e_10 = s[1]; return [3, v__do_e_10]; } case 4: { const v_r01 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_9 = s[1]; return [3, v__do_e_9]; } case 4: { const v_r02 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_8 = s[1]; return [3, v__do_e_8]; } case 4: { const v_r03 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_7 = s[1]; return [3, v__do_e_7]; } case 4: { const v_r04 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_6 = s[1]; return [3, v__do_e_6]; } case 4: { const v_r05 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_5 = s[1]; return [3, v__do_e_5]; } case 4: { const v_r06 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_4 = s[1]; return [3, v__do_e_4]; } case 4: { const v_r07 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_r08 = s[1]; return (v_appendTagged)(v_r08, "strWiden", (v_showStrA)(v_strWiden)); } } })((v_appendTagged)(v_r07, "nestedJustFalse", (v_showTwoA)((v_nestedUnion)([11, [2]])))); } } })((v_appendTagged)(v_r06, "nestedJustTrue", (v_showTwoA)((v_nestedUnion)([11, [1]])))); } } })((v_appendTagged)(v_r05, "nestedNothing", (v_showTwoA)((v_nestedUnion)((v__lift_21)([10]))))); } } })((v_appendTagged)(v_r04, "caseFalse", (v_showAB)((v_caseUnion)([2])))); } } })((v_appendTagged)(v_r03, "caseTrue", (v_showAB)((v_caseUnion)([1])))); } } })((v_appendTagged)(v_r02, "letBody", (v_showAB)(v_letBody))); } } })((v_appendTagged)(v_r01, "defBodyRight", (v_showAB)(v_defBodyRight))); } } })((v_tagged)("defBodyLeft", (v_showAB)(v_defBodyLeft)));

const v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_13__lift_14__lift_2__lift_23__lift_24__lift_3 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 36: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
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
                const v__cap34_0 = __s[1];
                const __t0 = (v__args[0] = 45, v__args[1] = v__cap34_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 35: {
                const v__cap35_0 = __s[1];
                const __t0 = (v__args[0] = 46, v__args[1] = v__cap35_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 37: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [58, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 38: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [59, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 39: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [60, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 40: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [61, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 41: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [62, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 42: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [63, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 43: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [64, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 44: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [65, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 45: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [66, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 46: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 36, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [67, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_13__lift_14__lift_2__lift_23__lift_24__lift_3 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_13__lift_14__lift_2__lift_23__lift_24__lift_3)(v__args, [57]);
};

const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_13__lift_14__lift_2__lift_23__lift_24__lift_3)([36, v__cl, v__arg0]);
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

const v__apply__lift_22 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 51: {
          return v__x;
        }
        case 52: {
          const v__pk_52 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_52;
          const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_22 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_22)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_22)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 52, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_22)(v__k, [8, [33, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_22)(v__k, [9, [34, v___f0]]);
        }
      }
    }
  }
};

const v__lift_22 = (v___input) => {
    return (v__cps__lift_22)(v___input, [51]);
};

const v__apply__lift_12 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 49: {
          return v__x;
        }
        case 50: {
          const v__pk_50 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_50;
          const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_12 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_12)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_12)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 50, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_12)(v__k, [8, [30, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_12)(v__k, [9, [31, v___f0]]);
        }
      }
    }
  }
};

const v__lift_12 = (v___input) => {
    return (v__cps__lift_12)(v___input, [49]);
};

const v_eitherToIO = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return (v_failIO)(v_e);
        }
        case 4: {
          const v_a = __s[1];
          return (v__lift_12)((v_pureIO)(v_a));
        }
      }
    }
};

const v__apply__lift_1 = (v__k, v__x) => {
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
          const __t1 = (v___input[0] = 48, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [32, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [35, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [47]);
};

const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
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

const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, (v_printErr)(v_e));
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
          return (v__apply__df_handleErrorIO_0)(v__k, [8, [26, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [9, [27, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_0 = (v_io) => {
    return (v__cps__df_handleErrorIO_0)(v_io, [53]);
};

const v__apply__df_andThenIO_3 = (v__k, v__x) => {
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

const v__cps__df_andThenIO_3 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, (v__lift_1)((v__bi_IO_Stdout_print)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [6, v_e]);
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
          return (v__apply__df_andThenIO_3)(v__k, [8, [28, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [9, [29, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_3 = (v_io) => {
    return (v__cps__df_andThenIO_3)(v_io, [55]);
};

const main = (v__df_handleErrorIO_0)((v__df_andThenIO_3)((v__lift_22)((v_eitherToIO)(v_render))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();