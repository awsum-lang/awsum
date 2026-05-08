"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

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

function main(v__input){
    return (v__df_handleErrorIO_0)(v_failingComputation);
}

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

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();