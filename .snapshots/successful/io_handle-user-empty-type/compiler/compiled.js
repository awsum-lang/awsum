"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }

function v_failIO(v_e){
    return [1, v_e];
}

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
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
        case 3: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = __t0;
          continue;
        }
      }
    }
  }
}

const v_failingComputation = (v_failIO)([0]);

function v_handleE1(v_e){
    {
      const __s = v_e;
      switch (__s[0]) {
        case 0: {
          return [2, "got E1", [0, [0]]];
        }
      }
    }
}

const main = (v__df_handleErrorIO_0)(v_failingComputation);

function v__df_handleErrorIO_0(v_io){
    return (v__cps__df_handleErrorIO_0)(v_io, [0]);
}

function v__cps__df_handleErrorIO_0(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [0, v_a]);
        }
        case 1: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, (v_handleE1)(v_e));
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = [1, v__k, v_s];
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 3: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [3, [0, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_handleErrorIO_0(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_1;
          const __t1 = [2, v_s, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__scc__apply1__df__lam_6_1(v__args){
    return (v__cps__scc__apply1__df__lam_6_1)(v__args, [0]);
}

function v__cps__scc__apply1__df__lam_6_1(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 0: {
                const v__cap0_0 = __s[1];
                const __t0 = [1, v__cap0_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 1: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = [0, v_cont, v_result];
          const __t1 = [1, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply__scc__apply1__df__lam_6_1(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const __t0 = v__pk_1;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply1(v__cl, v__arg0){
    return (v__scc__apply1__df__lam_6_1)([0, v__cl, v__arg0]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();