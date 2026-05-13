"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [13]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [3, [882564211, [14]]]; if (s < -2147483648) return [3, [3768445577, [13]]]; return [4, s|0]; }

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

function v_buildLeft(v_n, v_acc){
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
                const __t1 = [20, v_acc, (1|0), [19]];
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
}

function v_addOr0(v_a, v_b){
    {
      const __s = __addInt32(v_a, v_b);
      switch (__s[0]) {
        case 3: {
          const v__e = __s[1];
          return (0|0);
        }
        case 4: {
          const v_v = __s[1];
          return v_v;
        }
      }
    }
}

function v_sumTree(v_t, v_acc){
    return (v__cps_sumTree)(v_t, v_acc, [21]);
}

const main = ((s) => { switch(s[0]) { case 3: { const v__e = s[1]; return [7, "UNDERFLOW", [5, [0]]]; } case 4: { const v_t = s[1]; return [7, String((v_sumTree)(v_t, (0|0))), [5, [0]]]; } } })((v_buildLeft)((100000|0), [19]));

function v__scc__apply_sumTree__cps_sumTree(v__args){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 23: {
          const v__k = __s[1];
          const v__x = __s[2];
          {
            const __s = v__k;
            switch (__s[0]) {
              case 21: {
                return v__x;
              }
              case 22: {
                const v__pk_22 = __s[1];
                const v_r = __s[2];
                const __t0 = [24, v_r, v__x, v__pk_22];
                v__args = null;
                v__args = __t0;
                continue;
              }
            }
          }
        }
        case 24: {
          const v_t = __s[1];
          const v_acc = __s[2];
          const v__k = __s[3];
          {
            const __s = v_t;
            switch (__s[0]) {
              case 19: {
                const __t0 = [23, v__k, v_acc];
                v__args = null;
                v__args = __t0;
                continue;
              }
              case 20: {
                const v_l = __s[1];
                const v_v = __s[2];
                const v_r = __s[3];
                const __t0 = (v__args[0] = 24, v__args[1] = v_l, v__args[2] = (v_addOr0)(v_acc, v_v), v__args[3] = [22, v__k, v_r], v__args);
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

function v__cps_sumTree(v_t, v_acc, v__k){
    return (v__scc__apply_sumTree__cps_sumTree)([24, v_t, v_acc, v__k]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();