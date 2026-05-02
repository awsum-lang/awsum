"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [0] : [1]; }

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

function v_countDown(v_n){
  while (true) {
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
                const __t0 = v_m;
                v_n = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_showResult(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return ("left: " + (v_showUnderflowError)(v_e));
        }
        case 1: {
          const v_v = __s[1];
          return ("right: " + String(v_v));
        }
      }
    }
}

function main(v__input){
    return __print((v_showResult)((v_countDown)((100000|0))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();