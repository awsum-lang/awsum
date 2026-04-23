"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predUInt8(x){ return x === 0 ? [0, [0]] : [1, ((x - 1) & 0xFF)]; }
function __eqUInt8(a, b){ return a === b ? [0] : [1]; }

function v_showUnderflowError(v__wild0){
  return "UnderflowError";
}

const v_zero = (0 & 0xFF);

function v_countDown(v_n){
  return (v__cps_countDown)(v_n, [0]);
}

function v__cps_countDown(v_n, v__k){
  while (true) {
    {
      const __s = __eqUInt8(v_n, v_zero);
      switch (__s[0]) {
        case 0: {
          return (v__apply_countDown)(v__k, [1, String(v_n)]);
        }
        case 1: {
          {
            const __s = __predUInt8(v_n);
            switch (__s[0]) {
              case 0: {
                const v_e = __s[1];
                return (v__apply_countDown)(v__k, [0, v_e]);
              }
              case 1: {
                const v_m = __s[1];
                const __t0 = v_m;
                const __t1 = [1, v__k, v_n];
                v_n = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v__apply_countDown(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_n = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v_e = __s[1];
                const __t0 = v__pk_1;
                const __t1 = [0, v_e];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_s = __s[1];
                const __t0 = v__pk_1;
                const __t1 = [1, ((String(v_n) + ",") + v_s)];
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

function v_showResult(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_e = s[1]; return ("left: " + (v_showUnderflowError)(v_e)); } case 1: { const v_s = s[1]; return ("right: " + v_s); } } })(v_r);
}

const v_start = (255 & 0xFF);

function main(v__input){
  return __print((v_showResult)((v_countDown)(v_start)));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();