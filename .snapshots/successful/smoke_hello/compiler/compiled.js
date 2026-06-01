"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ const args = process.argv.slice(2); let list = [12]; for (let i = args.length - 1; i >= 0; i--) { const v = __entryArgEither(args[i]); if (v[0] !== 4) return v; list = [13, v[1], list]; } return [4, list]; }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

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
              case 19: {
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
              case 18: {
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
              case 22: {
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
        case 10: {
          return [3, v_e];
        }
        case 11: {
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
        case 12: {
          return [10];
        }
        case 13: {
          const v_h = __s[1];
          const v__t = __s[2];
          return [11, v_h];
        }
      }
    }
};

const v_failIO = (v_e) => {
    return [6, v_e];
};

const v__lift_32 = (v___input) => {
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

const v_greet = (v_args) => {
    {
      const __s = (v_nothingAsLeft)([22], (v__lift_32)((v_headList)(v_args)));
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

const v__lift_30 = (v___input) => {
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

const v__apply__lift_25 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 69: {
          return v__x;
        }
        case 70: {
          const v__pk_70 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_70;
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
          return (v__apply__lift_25)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 70, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_25)(v__k, [8, [39, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_25)(v__k, [9, [40, v___f0]]);
        }
      }
    }
  }
};

const v__lift_25 = (v___input) => {
    return (v__cps__lift_25)(v___input, [69]);
};

const v__apply__lift_19 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 67: {
          return v__x;
        }
        case 68: {
          const v__pk_68 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_68;
          const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_19 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_19)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_19)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 68, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_19)(v__k, [8, [37, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_19)(v__k, [9, [38, v___f0]]);
        }
      }
    }
  }
};

const v__lift_19 = (v___input) => {
    return (v__cps__lift_19)(v___input, [67]);
};

const v__apply__lift_16 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 65: {
          return v__x;
        }
        case 66: {
          const v__pk_66 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_66;
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
          const __t1 = (v___input[0] = 66, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [8, [34, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_16)(v__k, [9, [35, v___f0]]);
        }
      }
    }
  }
};

const v__lift_16 = (v___input) => {
    return (v__cps__lift_16)(v___input, [65]);
};

const v__apply__lift_12 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 63: {
          return v__x;
        }
        case 64: {
          const v__pk_64 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_64;
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
          const __t1 = (v___input[0] = 64, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_12)(v__k, [8, [32, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_12)(v__k, [9, [33, v___f0]]);
        }
      }
    }
  }
};

const v__lift_12 = (v___input) => {
    return (v__cps__lift_12)(v___input, [63]);
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

const v__lam_31 = (v_args) => {
    return (v_eitherToIO)((v__lift_30)((v_greet)(v_args)));
};

const v__apply__lift_1 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 61: {
          return v__x;
        }
        case 62: {
          const v__pk_62 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_62;
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
          const __t1 = (v___input[0] = 62, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [36, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [41, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [61]);
};

const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 71: {
          return v__x;
        }
        case 72: {
          const v__pk_72 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_72;
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
          return (v__apply__df_handleErrorIO_0)(v__k, (v_printError)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 72, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [8, [23, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [9, [24, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_0 = (v_io) => {
    return (v__cps__df_handleErrorIO_0)(v_io, [71]);
};

const v__apply__df_andThenIO_8 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 75: {
          return v__x;
        }
        case 76: {
          const v__pk_76 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_76;
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
          return (v__apply__df_andThenIO_8)(v__k, (v__lift_1)((v__lam_31)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_8)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 76, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_8)(v__k, [8, [29, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_8)(v__k, [9, [30, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_8 = (v_io) => {
    return (v__cps__df_andThenIO_8)(v_io, [75]);
};

const v__apply__df__rowspec_24_6 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 77: {
          return v__x;
        }
        case 78: {
          const v__pk_78 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_78;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df__rowspec_24_6 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df__rowspec_24_6)(v__k, (v__lam_31)(v_a));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df__rowspec_24_6)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 78, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_24_6)(v__k, [8, [27, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_24_6)(v__k, [9, [28, v_cont]]);
        }
      }
    }
  }
};

const v__df__rowspec_24_6 = (v_io) => {
    return (v__cps__df__rowspec_24_6)(v_io, [77]);
};

const v__apply__df__rowspec_15_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 73: {
          return v__x;
        }
        case 74: {
          const v__pk_74 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_74;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__df__rowspec_15_3 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df__rowspec_15_3)(v__k, (v__lift_16)((v__bi_IO_Stdout_print)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df__rowspec_15_3)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 74, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_15_3)(v__k, [8, [25, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df__rowspec_15_3)(v__k, [9, [26, v_cont]]);
        }
      }
    }
  }
};

const v__df__rowspec_15_3 = (v_io) => {
    return (v__cps__df__rowspec_15_3)(v_io, [73]);
};

const v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 79: {
          return v__x;
        }
        case 80: {
          const v__pk_80 = __s[1];
          const __t0 = v__pk_80;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 81: {
          const v__pk_81 = __s[1];
          const __t0 = v__pk_81;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 82: {
          const v__pk_82 = __s[1];
          const __t0 = v__pk_82;
          const __t1 = (v__df__rowspec_15_3)((v__lift_19)(v__x));
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 83: {
          const v__pk_83 = __s[1];
          const __t0 = v__pk_83;
          const __t1 = (v__df__rowspec_15_3)((v__lift_19)(v__x));
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 84: {
          const v__pk_84 = __s[1];
          const __t0 = v__pk_84;
          const __t1 = (v__df_andThenIO_8)((v__lift_25)(v__x));
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 85: {
          const v__pk_85 = __s[1];
          const __t0 = v__pk_85;
          const __t1 = (v__df_andThenIO_8)((v__lift_25)(v__x));
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 86: {
          const v__pk_86 = __s[1];
          const __t0 = v__pk_86;
          const __t1 = (v__df_andThenIO_8)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 87: {
          const v__pk_87 = __s[1];
          const __t0 = v__pk_87;
          const __t1 = (v__df_andThenIO_8)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 88: {
          const v__pk_88 = __s[1];
          const __t0 = v__pk_88;
          const __t1 = (v__lift_12)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 89: {
          const v__pk_89 = __s[1];
          const __t0 = v__pk_89;
          const __t1 = (v__lift_12)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 90: {
          const v__pk_90 = __s[1];
          const __t0 = v__pk_90;
          const __t1 = (v__lift_16)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 91: {
          const v__pk_91 = __s[1];
          const __t0 = v__pk_91;
          const __t1 = (v__lift_16)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 92: {
          const v__pk_92 = __s[1];
          const __t0 = v__pk_92;
          const __t1 = (v__lift_1)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 93: {
          const v__pk_93 = __s[1];
          const __t0 = v__pk_93;
          const __t1 = (v__lift_19)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 94: {
          const v__pk_94 = __s[1];
          const __t0 = v__pk_94;
          const __t1 = (v__lift_19)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 95: {
          const v__pk_95 = __s[1];
          const __t0 = v__pk_95;
          const __t1 = (v__lift_25)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 96: {
          const v__pk_96 = __s[1];
          const __t0 = v__pk_96;
          const __t1 = (v__lift_25)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 97: {
          const v__pk_97 = __s[1];
          const __t0 = v__pk_97;
          const __t1 = (v__lift_1)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 42: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 23: {
                const v__cap23_0 = __s[1];
                const __t0 = (v__args[0] = 43, v__args[1] = v__cap23_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 24: {
                const v__cap24_0 = __s[1];
                const __t0 = (v__args[0] = 44, v__args[1] = v__cap24_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 25: {
                const v__cap25_0 = __s[1];
                const __t0 = (v__args[0] = 45, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 26: {
                const v__cap26_0 = __s[1];
                const __t0 = (v__args[0] = 46, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 27: {
                const v__cap27_0 = __s[1];
                const __t0 = (v__args[0] = 47, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 28: {
                const v__cap28_0 = __s[1];
                const __t0 = (v__args[0] = 48, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 29: {
                const v__cap29_0 = __s[1];
                const __t0 = (v__args[0] = 49, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 30: {
                const v__cap30_0 = __s[1];
                const __t0 = (v__args[0] = 50, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 31: {
                return (v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3)(v__k, (v__io_getargs_cont)(v__arg0));
              }
              case 32: {
                const v__cap32_0 = __s[1];
                const __t0 = (v__args[0] = 51, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 33: {
                const v__cap33_0 = __s[1];
                const __t0 = (v__args[0] = 52, v__args[1] = v__cap33_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 34: {
                const v__cap34_0 = __s[1];
                const __t0 = (v__args[0] = 53, v__args[1] = v__cap34_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 35: {
                const v__cap35_0 = __s[1];
                const __t0 = (v__args[0] = 54, v__args[1] = v__cap35_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 36: {
                const v__cap36_0 = __s[1];
                const __t0 = (v__args[0] = 55, v__args[1] = v__cap36_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 37: {
                const v__cap37_0 = __s[1];
                const __t0 = (v__args[0] = 56, v__args[1] = v__cap37_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 38: {
                const v__cap38_0 = __s[1];
                const __t0 = (v__args[0] = 57, v__args[1] = v__cap38_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 39: {
                const v__cap39_0 = __s[1];
                const __t0 = (v__args[0] = 58, v__args[1] = v__cap39_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 40: {
                const v__cap40_0 = __s[1];
                const __t0 = (v__args[0] = 59, v__args[1] = v__cap40_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 41: {
                const v__cap41_0 = __s[1];
                const __t0 = (v__args[0] = 60, v__args[1] = v__cap41_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 43: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [80, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 44: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [81, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 45: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [82, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 46: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [83, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 47: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [84, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 48: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [85, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 49: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [86, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 50: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [87, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 51: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [88, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 52: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [89, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 53: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [90, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 54: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [91, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 55: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [92, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 56: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [93, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 57: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [94, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 58: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [95, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 59: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [96, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 60: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 42, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [97, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3)(v__args, [79]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3)([42, v__cl, v__arg0]);
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

const main = (v__df_handleErrorIO_0)((v__df__rowspec_15_3)((v__lift_19)((v__df__rowspec_24_6)([8, [31]]))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();