"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [3, [882564211, [17]]]; if (s < -2147483648) return [3, [3768445577, [16]]]; return [4, s|0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [18]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [19]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [19]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [19]]]; } return [4, arg]; }
function __getArgs(){ const args = process.argv.slice(2); let list = [12]; for (let i = args.length - 1; i >= 0; i--) { const v = __entryArgEither(args[i]); if (v[0] !== 4) return v; list = [13, v[1], list]; } return [4, list]; }
function __stdinReadAll(){ return __entryArgEither(require('fs').readFileSync(0).toString('utf-8')); }

const v_pureEither = (v_x) => {
    return [4, v_x];
};

const v_opTuple = (v__wild0) => {
    return [4, [15, (1|0), (2|0), (3|0)]];
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

const v_handleInputErr = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 502975519: {
          const v__u = __s[1];
          return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
        }
        case 589989748: {
          const v__l = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
};

const v__let_12 = (v_res) => {
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "PARSE_ERROR", [5, [0]]];
        }
        case 4: {
          const v_n = __s[1];
          return [7, String(v_n), [5, [0]]];
        }
      }
    }
};

const v_processInput = (v_raw) => {
    return (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, v__do_e_0]; } case 4: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 15: { const v_a = s[1]; const v_b = s[2]; const v_c = s[3]; return (v_pureEither)(((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return v_c; } case 4: { const v_ab = s[1]; return ((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return v_c; } case 4: { const v_abc = s[1]; return v_abc; } } })(__addInt32(v_ab, v_c)); } } })(__addInt32(v_a, v_b))); } } })(v___p0); } } })((v_opTuple)(v_raw)));
};

const v_processArgs = (v_args) => {
    {
      const __s = (v_headList)(v_args);
      switch (__s[0]) {
        case 10: {
          return [7, "NO_ARG", [5, [0]]];
        }
        case 11: {
          const v_first = __s[1];
          return (v_processInput)(v_first);
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

const v__apply__lift_1 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 30: {
          return v__x;
        }
        case 31: {
          const v__pk_31 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_31;
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
          const __t1 = (v___input[0] = 31, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [21, v___f0]]);
        }
        case 9: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [9, [22, v___f0]]);
        }
      }
    }
  }
};

const v__lift_1 = (v___input) => {
    return (v__cps__lift_1)(v___input, [30]);
};

const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 32: {
          return v__x;
        }
        case 33: {
          const v__pk_33 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_33;
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
          return (v__apply__df_handleErrorIO_0)(v__k, (v_handleInputErr)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 33, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [8, [16, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [9, [17, v_cont]]);
        }
      }
    }
  }
};

const v__df_handleErrorIO_0 = (v_io) => {
    return (v__cps__df_handleErrorIO_0)(v_io, [32]);
};

const v__apply__df_andThenIO_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 34: {
          return v__x;
        }
        case 35: {
          const v__pk_35 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_35;
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
          return (v__apply__df_andThenIO_3)(v__k, (v__lift_1)((v_processArgs)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = (v_io[0] = 35, v_io[1] = v__k, v_io[2] = v_s, v_io);
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [8, [18, v_cont]]);
        }
        case 9: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_3)(v__k, [9, [19, v_cont]]);
        }
      }
    }
  }
};

const v__df_andThenIO_3 = (v_io) => {
    return (v__cps__df_andThenIO_3)(v_io, [34]);
};

const v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 36: {
          return v__x;
        }
        case 37: {
          const v__pk_37 = __s[1];
          const __t0 = v__pk_37;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 38: {
          const v__pk_38 = __s[1];
          const __t0 = v__pk_38;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 39: {
          const v__pk_39 = __s[1];
          const __t0 = v__pk_39;
          const __t1 = (v__df_andThenIO_3)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 40: {
          const v__pk_40 = __s[1];
          const __t0 = v__pk_40;
          const __t1 = (v__df_andThenIO_3)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 41: {
          const v__pk_41 = __s[1];
          const __t0 = v__pk_41;
          const __t1 = (v__lift_1)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 42: {
          const v__pk_42 = __s[1];
          const __t0 = v__pk_42;
          const __t1 = (v__lift_1)(v__x);
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
        case 23: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 16: {
                const v__cap16_0 = __s[1];
                const __t0 = (v__args[0] = 24, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 17: {
                const v__cap17_0 = __s[1];
                const __t0 = (v__args[0] = 25, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 18: {
                const v__cap18_0 = __s[1];
                const __t0 = (v__args[0] = 26, v__args[1] = v__cap18_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 19: {
                const v__cap19_0 = __s[1];
                const __t0 = (v__args[0] = 27, v__args[1] = v__cap19_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 20: {
                return (v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3)(v__k, (v__io_getargs_cont)(v__arg0));
              }
              case 21: {
                const v__cap21_0 = __s[1];
                const __t0 = (v__args[0] = 28, v__args[1] = v__cap21_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 22: {
                const v__cap22_0 = __s[1];
                const __t0 = (v__args[0] = 29, v__args[1] = v__cap22_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 24: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [37, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 25: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [38, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 26: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [39, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 27: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [40, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 28: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 23, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [41, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 29: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = (v__args[0] = 23, v__args[1] = v___f, v__args[2] = v___arg, v__args);
          const __t1 = [42, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3 = (v__args) => {
    return (v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3)(v__args, [36]);
};

const v__apply1 = (v__cl, v__arg0) => {
    return (v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_4_4__df__lam_5_5__lift_2__lift_3)([23, v__cl, v__arg0]);
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

const main = (v__df_handleErrorIO_0)((v__df_andThenIO_3)([8, [20]]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();