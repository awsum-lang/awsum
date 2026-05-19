"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [14]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }

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
      }
    }
  }
}

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

const main = ((s) => { switch(s[0]) { case 3: { const v_e = s[1]; return [7, (v_showUnderflowError)(v_e), [5, [0]]]; } case 4: { const v_v = s[1]; return [7, String(v_v), [5, [0]]]; } } })((v_stepA)((1000000|0)));

function v__scc_stepA_stepB_stepC(v__args){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 8: {
          const v_n = __s[1];
          {
            const __s = __eqInt32(v_n, (0|0));
            switch (__s[0]) {
              case 1: {
                return [4, (0|0)];
              }
              case 2: {
                {
                  const __s = __predInt32(v_n);
                  switch (__s[0]) {
                    case 3: {
                      const v_e = __s[1];
                      return [3, v_e];
                    }
                    case 4: {
                      const v_m = __s[1];
                      const __t0 = (v__args[0] = 9, v__args[1] = v_m, v__args);
                      v__args = __t0;
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 9: {
          const v_n = __s[1];
          {
            const __s = __eqInt32(v_n, (0|0));
            switch (__s[0]) {
              case 1: {
                return [4, (0|0)];
              }
              case 2: {
                {
                  const __s = __predInt32(v_n);
                  switch (__s[0]) {
                    case 3: {
                      const v_e = __s[1];
                      return [3, v_e];
                    }
                    case 4: {
                      const v_m = __s[1];
                      const __t0 = (v__args[0] = 10, v__args[1] = v_m, v__args);
                      v__args = __t0;
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 10: {
          const v_n = __s[1];
          {
            const __s = __eqInt32(v_n, (0|0));
            switch (__s[0]) {
              case 1: {
                return [4, (0|0)];
              }
              case 2: {
                {
                  const __s = __predInt32(v_n);
                  switch (__s[0]) {
                    case 3: {
                      const v_e = __s[1];
                      return [3, v_e];
                    }
                    case 4: {
                      const v_m = __s[1];
                      const __t0 = (v__args[0] = 8, v__args[1] = v_m, v__args);
                      v__args = __t0;
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

function v_stepA(v_n){
    return (v__scc_stepA_stepB_stepC)([8, v_n]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();