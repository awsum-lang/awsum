"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [16]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }

const v_spineLast = (v_t, v_lastV) => {
  while (true) {
    {
      const __s = v_t;
      switch (__s[0]) {
        case 22: {
          return v_lastV;
        }
        case 23: {
          const v_l = __s[1];
          const v_v = __s[2];
          const v__r = __s[3];
          const __t0 = v_l;
          const __t1 = v_v;
          v_lastV = null;
          v_t = null;
          v_t = __t0;
          v_lastV = __t1;
          continue;
        }
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

const v_buildRight = (v_n, v_acc) => {
  while (true) {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return [4, v_acc];
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
                const __t0 = v_m;
                const __t1 = [23, [22], v_n, v_acc];
                v_acc = null;
                v_n = null;
                v_n = __t0;
                v_acc = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v__scc__apply_mirror__cps_mirror = (v__args) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 27: {
          const v__k = __s[1];
          const v__x = __s[2];
          {
            const __s = v__k;
            switch (__s[0]) {
              case 24: {
                return v__x;
              }
              case 26: {
                const v__pk_26 = __s[1];
                const v__rcv_0 = __s[2];
                const v_v = __s[3];
                const __t0 = (v__args[0] = 27, v__args[1] = v__pk_26, v__args[2] = [23, v__rcv_0, v_v, v__x], v__args);
                v__args = __t0;
                continue;
              }
              case 25: {
                const v__pk_25 = __s[1];
                const v_l = __s[2];
                const v_v = __s[3];
                const __t0 = (v__args[0] = 28, v__args[1] = v_l, v__args[2] = [26, v__pk_25, v__x, v_v], v__args);
                v__args = __t0;
                continue;
              }
            }
          }
        }
        case 28: {
          const v_t = __s[1];
          const v__k = __s[2];
          {
            const __s = v_t;
            switch (__s[0]) {
              case 22: {
                const __t0 = (v__args[0] = 27, v__args[1] = v__k, v__args[2] = [22], v__args);
                v__args = __t0;
                continue;
              }
              case 23: {
                const v_l = __s[1];
                const v_v = __s[2];
                const v_r = __s[3];
                const __t0 = (v__args[0] = 28, v__args[1] = v_r, v__args[2] = [25, v__k, v_l, v_v], v__args);
                v__args = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v__cps_mirror = (v_t, v__k) => {
    return (v__scc__apply_mirror__cps_mirror)([28, v_t, v__k]);
};

const v_mirror = (v_t) => {
    return (v__cps_mirror)(v_t, [24]);
};

const main = ((s) => { switch(s[0]) { case 3: { const v__e = s[1]; return [7, "UNDERFLOW", [5, [0]]]; } case 4: { const v_t = s[1]; return [7, String((v_spineLast)((v_mirror)(v_t), (0|0))), [5, [0]]]; } } })((v_buildRight)((100000|0), [22]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();