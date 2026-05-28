"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

const v_handleRemainingErrors = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 63694499: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 22: {
                return [7, "got E1", [5, [0]]];
              }
            }
          }
        }
        case 80472118: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 23: {
                return [7, "got E2", [5, [0]]];
              }
            }
          }
        }
      }
    }
};

const v_failIO = (v_e) => {
    return [6, v_e];
};

const v_failingComputation = (v_failIO)([63694499, [22]]);

const v_handleSomeErrors = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 63694499: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 22: {
                return (v_failIO)([63694499, [22]]);
              }
            }
          }
        }
        case 80472118: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 23: {
                return (v_failIO)([80472118, [23]]);
              }
            }
          }
        }
      }
    }
};

const v__cps__scc__apply1__df__lam_10_1__df__lam_10_4__df__lam_11_2__df__lam_11_5 = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 28: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 24: {
                const v__cap24_0 = __s[1];
                const __t0 = (v__args[0] = 29, v__args[1] = v__cap24_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 25: {
                const v__cap25_0 = __s[1];
                const __t0 = (v__args[0] = 30, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 26: {
                const v__cap26_0 = __s[1];
                const __t0 = (v__args[0] = 31, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 27: {
                const v__cap27_0 = __s[1];
                const __t0 = (v__args[0] = 32, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 29: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 28, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [38, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 30: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 28, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [39, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 31: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 28, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [40, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 32: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 28, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [41, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_10_1__df__lam_10_4__df__lam_11_2__df__lam_11_5 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_10_1__df__lam_10_4__df__lam_11_2__df__lam_11_5)(v__args, [37]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_10_1__df__lam_10_4__df__lam_11_2__df__lam_11_5)([28, v__cl, v__arg0]);
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

const v__apply__df_handleErrorIO_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 35: {
          return v__x;
        }
        case 36: {
          const v__pk_36 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_36;
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

const v__cps__df_handleErrorIO_3 = (v_io, v__k) => {
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_3)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_3)(v__k, (v_handleSomeErrors)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 36, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v__k = null;
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_3)(v__k, [8, [25, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_3)(v__k, [9, [27, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_3 = (v_io) => {
    return (v__cps__df_handleErrorIO_3)(v_io, [35]);
};

const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
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
          return (v__apply__df_handleErrorIO_0)(v__k, (v_handleRemainingErrors)(v_e));
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
          return (v__apply__df_handleErrorIO_0)(v__k, [8, [24, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [9, [26, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_0 = (v_io) => {
    return (v__cps__df_handleErrorIO_0)(v_io, [33]);
};

const main = (v__df_handleErrorIO_0)((v__df_handleErrorIO_3)(v_failingComputation));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();