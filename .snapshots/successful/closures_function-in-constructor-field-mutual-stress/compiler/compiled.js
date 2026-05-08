"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [0] : [1]; }

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

const v_bBox = [0, [0]];

const main = ((s) => { switch(s[0]) { case 0: { const v__e = s[1]; return [2, "underflow", [0, [0]]]; } case 1: { const v_v = s[1]; return [2, String(v_v), [0, [0]]]; } } })((v_a)((1000000|0)));

function v__scc__apply1__lam_7_a_b(v__args){
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
                const __t0 = [1, v__arg0];
                v__args = __t0;
                continue;
              }
            }
          }
        }
        case 1: {
          const v_n = __s[1];
          const __t0 = [3, v_n];
          v__args = __t0;
          continue;
        }
        case 2: {
          const v_n = __s[1];
          {
            const __s = __eqInt32(v_n, (0|0));
            switch (__s[0]) {
              case 0: {
                return [1, (0|0)];
              }
              case 1: {
                {
                  const __s = __predInt32(v_n);
                  switch (__s[0]) {
                    case 0: {
                      const v_e = __s[1];
                      return [0, v_e];
                    }
                    case 1: {
                      const v_m = __s[1];
                      {
                        const __s = v_bBox;
                        switch (__s[0]) {
                          case 0: {
                            const v_f = __s[1];
                            const __t0 = [0, v_f, v_m];
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
        case 3: {
          const v_n = __s[1];
          {
            const __s = __eqInt32(v_n, (0|0));
            switch (__s[0]) {
              case 0: {
                return [1, (0|0)];
              }
              case 1: {
                {
                  const __s = __predInt32(v_n);
                  switch (__s[0]) {
                    case 0: {
                      const v_e = __s[1];
                      return [0, v_e];
                    }
                    case 1: {
                      const v_m = __s[1];
                      const __t0 = [2, v_m];
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

function v_a(v_n){
    return (v__scc__apply1__lam_7_a_b)([2, v_n]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();