"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [15]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [16]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [16]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [16]]]; } return [4, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }

function v_failIO(v_e){
    return [6, v_e];
}

function v_runIO(v_io){
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
      }
    }
  }
}

const v_action = (v_failIO)([19]);

function v_handler(v__b){
    return [7, "ErrB", [5, [0]]];
}

const main = (v__let_8)((v__df_mapIOError_0)(v_action));

function v__lam_7(v__a){
    return [20];
}

function v__let_8(v_renamed){
    return (v__df_handleErrorIO_2)(v_renamed);
}

function v__df_mapIOError_0(v_io){
    return (v__cps__df_mapIOError_0)(v_io, [26]);
}

function v__cps__df_mapIOError_0(v_io, v__k){
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
          return (v__apply__df_mapIOError_0)(v__k, [6, (v__lam_7)(v_e)]);
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
          return (v__apply__df_mapIOError_0)(v__k, [8, [21, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_mapIOError_0(v__k, v__x){
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
}

function v__df_handleErrorIO_2(v_io){
    return (v__cps__df_handleErrorIO_2)(v_io, [28]);
}

function v__cps__df_handleErrorIO_2(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_2)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_2)(v__k, (v_handler)(v_e));
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
          return (v__apply__df_handleErrorIO_2)(v__k, [8, [22, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_handleErrorIO_2(v__k, v__x){
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
}

function v__scc__apply1__df__lam_5_1__df__lam_6_3(v__args){
    return (v__cps__scc__apply1__df__lam_5_1__df__lam_6_3)(v__args, [30]);
}

function v__cps__scc__apply1__df__lam_5_1__df__lam_6_3(v__args, v__k){
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
              case 21: {
                const v__cap21_0 = __s[1];
                const __t0 = (v__args[0] = 24, v__args[1] = v__cap21_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 22: {
                const v__cap22_0 = __s[1];
                const __t0 = (v__args[0] = 25, v__args[1] = v__cap22_0, v__args[2] = v__arg0, v__args);
                const __t1 = v__k;
                v__k = null;
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
          const __t1 = [31, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 25: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = (v__args[0] = 23, v__args[1] = v_cont, v__args[2] = v_result, v__args);
          const __t1 = [32, v__k];
          v__k = null;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply1(v__cl, v__arg0){
    return (v__scc__apply1__df__lam_5_1__df__lam_6_3)([23, v__cl, v__arg0]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();