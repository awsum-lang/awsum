"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [14]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }

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

const v_identity = (v_n) => {
    return v_n;
};

const v__apply1 = (v__cl, v__arg0) => {
    {
      const __s = v__cl;
      switch (__s[0]) {
        case 21: {
          return (v_identity)(v__arg0);
        }
      }
    }
};

const v__apply_countWithBox = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 22: {
          return v__x;
        }
        case 23: {
          const v__pk_23 = __s[1];
          const v_b = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v_e = __s[1];
                const __t0 = v__pk_23;
                const __t1 = (v__x[0] = 3, v__x[1] = v_e, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_v = __s[1];
                {
                  const __s = v_b;
                  switch (__s[0]) {
                    case 20: {
                      const v_f = __s[1];
                      const __t0 = v__pk_23;
                      const __t1 = (v__x[0] = 4, v__x[1] = (v__apply1)(v_f, v_v), v__x);
                      v__k = null;
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
    }
  }
};

const v__cps_countWithBox = (v_b, v_n, v__k) => {
  while (true) {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return (v__apply_countWithBox)(v__k, [4, (0|0)]);
        }
        case 2: {
          {
            const __s = __predInt32(v_n);
            switch (__s[0]) {
              case 3: {
                const v_e = __s[1];
                return (v__apply_countWithBox)(v__k, [3, v_e]);
              }
              case 4: {
                const v_m = __s[1];
                const __t0 = v_b;
                const __t1 = v_m;
                const __t2 = [23, v__k, v_b];
                v__k = null;
                v_n = null;
                v_b = null;
                v_b = __t0;
                v_n = __t1;
                v__k = __t2;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v_countWithBox = (v_b, v_n) => {
    return (v__cps_countWithBox)(v_b, v_n, [22]);
};

const main = ((s) => { switch(s[0]) { case 3: { const v__e = s[1]; return [7, "underflow", [5, [0]]]; } case 4: { const v_v = s[1]; return [7, String(v_v), [5, [0]]]; } } })((v_countWithBox)([20, [21]], (1000000|0)));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();