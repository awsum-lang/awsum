"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [0] : [1]; }

function v_showUnderflowError(v__wild0){
  return "UnderflowError";
}

const v_zero = (0|0);

function v_showResult(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_e = s[1]; return ("left: " + (v_showUnderflowError)(v_e)); } case 1: { const v_v = s[1]; return ("right: " + String(v_v)); } } })(v_r);
}

const v_start = (100000|0);

function main(v__input){
  return __print((v_showResult)((v_pingOne)(v_start)));
}

function v__scc_pingOne_pongTwo(v__args){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v_n = __s[1];
          {
            const __s = __eqInt32(v_n, v_zero);
            switch (__s[0]) {
              case 0: {
                return [1, v_zero];
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
                      const __t0 = [1, v_m, v_zero];
                      v__args = __t0;
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 1: {
          const v_n = __s[1];
          const v__acc = __s[2];
          {
            const __s = __eqInt32(v_n, v_zero);
            switch (__s[0]) {
              case 0: {
                return [1, v_zero];
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
                      const __t0 = [0, v_m];
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

function v_pingOne(v_n){
  return (v__scc_pingOne_pongTwo)([0, v_n]);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();