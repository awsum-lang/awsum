"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [16]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

const v_showUnderflowError = (v__wild0) => {
    return "UnderflowError";
};

const v_showResult = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return __concat("left: ", (v_showUnderflowError)(v_e));
        }
        case 4: {
          const v_v = __s[1];
          return __concat("right: ", String(v_v));
        }
      }
    }
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
      }
    }
  }
};

const v__scc_pingOne_pongTwo = (v__args) => {
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
                      const __t0 = [9, v_m, (0|0)];
                      v__args = null;
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
          const v__acc = __s[2];
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
                      const __t0 = [8, v_m];
                      v__args = null;
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
};

const v_pingOne = (v_n) => {
    return (v__scc_pingOne_pongTwo)([8, v_n]);
};

const v__let_12 = (v_res) => {
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
};

const main = (v__let_12)((v_showResult)((v_pingOne)((100000|0))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();