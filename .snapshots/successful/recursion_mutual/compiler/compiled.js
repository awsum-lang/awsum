"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function main(v__input){
    return (v__let_1)((v_handleA)([0]));
}

function v__let_1(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("STRING_TOO_LONG");
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

function v__scc_handleA_handleB(v__args){
    return (v__cps__scc_handleA_handleB)(v__args, [0]);
}

function v__cps__scc_handleA_handleB(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 0: {
                const __t0 = [1, [1]];
                const __t1 = [1, v__k];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 1: {
                const __t0 = [1, v_step];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 2: {
                const __t0 = [1, v_step];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 3: {
                return (v__apply__scc_handleA_handleB)(v__k, [1, ""]);
              }
            }
          }
        }
        case 1: {
          const v_step = __s[1];
          {
            const __s = v_step;
            switch (__s[0]) {
              case 0: {
                const __t0 = [0, v_step];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 1: {
                const __t0 = [0, [2]];
                const __t1 = [2, v__k];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 2: {
                const __t0 = [0, [3]];
                const __t1 = [3, v__k];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 3: {
                return (v__apply__scc_handleA_handleB)(v__k, [1, ""]);
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
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v__do_e_9_5 = __s[1];
                const __t0 = v__pk_1;
                const __t1 = [0, v__do_e_9_5];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_rest = __s[1];
                const __t0 = v__pk_1;
                const __t1 = [1, ("A" + v_rest)];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
        case 2: {
          const v__pk_2 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v__do_e_18_5 = __s[1];
                const __t0 = v__pk_2;
                const __t1 = [0, v__do_e_18_5];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_rest = __s[1];
                const __t0 = v__pk_2;
                const __t1 = [1, ("B" + v_rest)];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
        case 3: {
          const v__pk_3 = __s[1];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v__do_e_22_5 = __s[1];
                const __t0 = v__pk_3;
                const __t1 = [0, v__do_e_22_5];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_rest = __s[1];
                const __t0 = v__pk_3;
                const __t1 = [1, ("C" + v_rest)];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_handleA(v_step){
    return (v__scc_handleA_handleB)([0, v_step]);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();