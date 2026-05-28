"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

const v_say = (v__eta0) => {
    return [7, v__eta0, [5, [0]]];
};

const v_handleInputErr = (v__e) => {
    return [7, "INPUT_ERROR", [5, [0]]];
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

const v__apply__lift_1 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 24: {
          return v__x;
        }
        case 25: {
          const v__pk_25 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_25;
          const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__x = null;
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
          const __t1 = (v___input[0] = 25, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [15, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [16, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [24]);
};

const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 26: {
          return v__x;
        }
        case 27: {
          const v__pk_27 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_27;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__x = null;
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
          return (v__apply__df_handleErrorIO_0)(v__k, (v_handleInputErr)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 27, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [8, [10, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [9, [11, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_0 = (v_io) => {
    return (v__cps__df_handleErrorIO_0)(v_io, [26]);
};

const v__apply__df_andThenIO_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          const v__pk_29 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_29;
          const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
          v__x = null;
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
          return (v__apply__df_andThenIO_3)(v__k, (v__lift_1)((v_say)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 29, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [8, [12, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [9, [13, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_3 = (v_io) => {
    return (v__cps__df_andThenIO_3)(v_io, [28]);
};

const v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 30: {
          return v__x;
        }
        case 31: {
          const v__pk_31 = __s[1];
          const __t0 = v__pk_31;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 32: {
          const v__pk_32 = __s[1];
          const __t0 = v__pk_32;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 33: {
          const v__pk_33 = __s[1];
          const __t0 = v__pk_33;
          const __t1 = (v__df_andThenIO_3)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 34: {
          const v__pk_34 = __s[1];
          const __t0 = v__pk_34;
          const __t1 = (v__df_andThenIO_3)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 35: {
          const v__pk_35 = __s[1];
          const __t0 = v__pk_35;
          const __t1 = (v__lift_1)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 36: {
          const v__pk_36 = __s[1];
          const __t0 = v__pk_36;
          const __t1 = (v__lift_1)(v__x);
          v__x = null;
          v__k = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 17: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 10: {
                const v__cap10_0 = __s[1];
                const __t0 = (v__args[0] = 18, v__args[1] = v__cap10_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 11: {
                const v__cap11_0 = __s[1];
                const __t0 = (v__args[0] = 19, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 12: {
                const v__cap12_0 = __s[1];
                const __t0 = (v__args[0] = 20, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 13: {
                const v__cap13_0 = __s[1];
                const __t0 = (v__args[0] = 21, v__args[1] = v__cap13_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 14: {
                return (v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3)(v__k, (v__io_getargs_cont)(v__arg0));
              }
              case 15: {
                const v__cap15_0 = __s[1];
                const __t0 = (v__args[0] = 22, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 16: {
                const v__cap16_0 = __s[1];
                const __t0 = (v__args[0] = 23, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 18: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 17, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [31, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 19: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 17, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [32, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 20: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 17, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [33, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 21: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 17, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [34, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 22: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 17, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [35, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 23: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 17, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [36, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3)(v__args, [30]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3)([17, v__cl, v__arg0]);
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
                v_io = null;
                v_io = __t0;
                continue;
              }
            }
          }
        }
        case 8: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = null;
          v_io = __t0;
          continue;
        }
        case 9: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __stdinReadAll());
          v_io = null;
          v_io = __t0;
          continue;
        }
      }
    }
  }
};

const main = (v__df_handleErrorIO_0)((v__df_andThenIO_3)([8, [14]]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();