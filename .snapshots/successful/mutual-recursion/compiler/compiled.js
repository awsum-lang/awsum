"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function main(v__input){
  return __print((v_handleA)([0]));
}

function v__scc_handleA_handleB(v__fn, v__arg_0){
  return (v__cps__scc_handleA_handleB)(v__fn, v__arg_0, [0]);
}

function v__cps__scc_handleA_handleB(v__fn, v__arg_0, v__k){
  while (true) {
    {
      const __s = v__fn;
      switch (__s[0]) {
        case 0: {
          {
            const __s = v__arg_0;
            switch (__s[0]) {
              case 0: {
                const __t0 = [1];
                const __t1 = [1];
                const __t2 = [1, v__k];
                v__fn = __t0;
                v__arg_0 = __t1;
                v__k = __t2;
                continue;
              }
              case 1: {
                const __t0 = [1];
                const __t1 = v__arg_0;
                const __t2 = v__k;
                v__fn = __t0;
                v__arg_0 = __t1;
                v__k = __t2;
                continue;
              }
              case 2: {
                const __t0 = [1];
                const __t1 = v__arg_0;
                const __t2 = v__k;
                v__fn = __t0;
                v__arg_0 = __t1;
                v__k = __t2;
                continue;
              }
              case 3: {
                return (v__apply__scc_handleA_handleB)(v__k, "");
              }
            }
          }
        }
        case 1: {
          {
            const __s = v__arg_0;
            switch (__s[0]) {
              case 0: {
                const __t0 = [0];
                const __t1 = v__arg_0;
                const __t2 = v__k;
                v__fn = __t0;
                v__arg_0 = __t1;
                v__k = __t2;
                continue;
              }
              case 1: {
                const __t0 = [0];
                const __t1 = [2];
                const __t2 = [2, v__k];
                v__fn = __t0;
                v__arg_0 = __t1;
                v__k = __t2;
                continue;
              }
              case 2: {
                const __t0 = [0];
                const __t1 = [3];
                const __t2 = [3, v__k];
                v__fn = __t0;
                v__arg_0 = __t1;
                v__k = __t2;
                continue;
              }
              case 3: {
                return (v__apply__scc_handleA_handleB)(v__k, "");
              }
            }
          }
        }
      }
    }
  }
}

function v__apply__scc_handleA_handleB(v__k, v__x){
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
          const __t1 = ("A" + v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 2: {
          const v__pk_2 = __s[1];
          const __t0 = v__pk_2;
          const __t1 = ("B" + v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 3: {
          const v__pk_3 = __s[1];
          const __t0 = v__pk_3;
          const __t1 = ("C" + v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v_handleA(v_step){
  return (v__scc_handleA_handleB)([0], v_step);
}

function v_handleB(v_step){
  return (v__scc_handleA_handleB)([1], v_step);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();