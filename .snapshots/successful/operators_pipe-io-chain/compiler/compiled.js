"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [16]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [17]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [17]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [17]]]; } return [4, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

const v__lam_12 = (v__u) => {
    return [7, "c", [5, [0]]];
};

const v__cps__scc__apply1__df__lam_4_1__df__lam_4_4__df__lam_5_2__df__lam_5_5__lift_14__lift_15__lift_2__lift_3 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 18: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 10: {
                const v__cap10_0 = __s[1];
                const __t0 = (v__args[0] = 19, v__args[1] = v__cap10_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 11: {
                const v__cap11_0 = __s[1];
                const __t0 = (v__args[0] = 20, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 12: {
                const v__cap12_0 = __s[1];
                const __t0 = (v__args[0] = 21, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 13: {
                const v__cap13_0 = __s[1];
                const __t0 = (v__args[0] = 22, v__args[1] = v__cap13_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 14: {
                const v__cap14_0 = __s[1];
                const __t0 = (v__args[0] = 23, v__args[1] = v__cap14_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 15: {
                const v__cap15_0 = __s[1];
                const __t0 = (v__args[0] = 24, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 16: {
                const v__cap16_0 = __s[1];
                const __t0 = (v__args[0] = 25, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 17: {
                const v__cap17_0 = __s[1];
                const __t0 = (v__args[0] = 26, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 19: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [36, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 20: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [37, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 21: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [38, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 22: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [39, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 23: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [40, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 24: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [41, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 25: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [42, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 26: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 18, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [43, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_4_1__df__lam_4_4__df__lam_5_2__df__lam_5_5__lift_14__lift_15__lift_2__lift_3 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_4_1__df__lam_4_4__df__lam_5_2__df__lam_5_5__lift_14__lift_15__lift_2__lift_3)(v__args, [35]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_4_1__df__lam_4_4__df__lam_5_2__df__lam_5_5__lift_14__lift_15__lift_2__lift_3)([18, v__cl, v__arg0]);
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

const v__apply__lift_13 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 29: {
          return v__x;
        }
        case 30: {
          const v__pk_30 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_30;
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

const v__cps__lift_13 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_13)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_13)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 30, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_13)(v__k, [8, [14, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_13)(v__k, [9, [15, v___f0]]);
        }
      }
    }
  }
};

const v__lift_13 = (v___input) => {
    return (v__cps__lift_13)(v___input, [29]);
};

const v__lam_16 = (v__u) => {
    return (v__lift_13)([7, "b", [5, [0]]]);
};

const v__apply__lift_1 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_28;
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
          const __t1 = (v___input[0] = 28, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [16, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [17, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [27]);
};

const v__apply__df_andThenIO_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 33: {
          return v__x;
        }
        case 34: {
          const v__pk_34 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_34;
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
          return (v__apply__df_andThenIO_3)(v__k, (v__lift_1)((v__lam_16)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 34, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [8, [11, v_cont]]);
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
    return (v__cps__df_andThenIO_3)(v_io, [33]);
};

const v__apply__df_andThenIO_0 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 31: {
          return v__x;
        }
        case 32: {
          const v__pk_32 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_32;
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

const v__cps__df_andThenIO_0 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, (v__lift_1)((v__lam_12)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 32, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
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
          return (v__apply__df_andThenIO_0)(v__k, [9, [12, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_0 = (v_io) => {
    return (v__cps__df_andThenIO_0)(v_io, [31]);
};

const main = (v__df_andThenIO_0)((v__df_andThenIO_3)((v__lift_13)([7, "a", [5, [0]]])));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();