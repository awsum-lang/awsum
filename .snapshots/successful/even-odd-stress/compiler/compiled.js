"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [0] : [1]; }

function v_showUnderflowError(v__wild0){
  return "UnderflowError";
}

const v_zero = (0|0);

function v_showBool(v_b){
  return ((s) => { switch(s[0]) { case 0: { return "true"; } case 1: { return "false"; } } })(v_b);
}

function v_showResult(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_e = s[1]; return ("left: " + (v_showUnderflowError)(v_e)); } case 1: { const v_b = s[1]; return ("right: " + (v_showBool)(v_b)); } } })(v_r);
}

const v_start = (1000000|0);

function main(v__input){
  return __print((v_showResult)((v_evenInt)(v_start)));
}

function v__scc_evenInt_oddInt(v__fn, v__arg_0){
  while (true) {
    {
      const __s = v__fn;
      switch (__s[0]) {
        case 0: {
          {
            const __s = __eqInt32(v__arg_0, v_zero);
            switch (__s[0]) {
              case 0: {
                return [1, [0]];
              }
              case 1: {
                {
                  const __s = __predInt32(v__arg_0);
                  switch (__s[0]) {
                    case 0: {
                      const v_e = __s[1];
                      return [0, v_e];
                    }
                    case 1: {
                      const v_m = __s[1];
                      const __t0 = [1];
                      const __t1 = v_m;
                      v__fn = __t0;
                      v__arg_0 = __t1;
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
        case 1: {
          {
            const __s = __eqInt32(v__arg_0, v_zero);
            switch (__s[0]) {
              case 0: {
                return [1, [1]];
              }
              case 1: {
                {
                  const __s = __predInt32(v__arg_0);
                  switch (__s[0]) {
                    case 0: {
                      const v_e = __s[1];
                      return [0, v_e];
                    }
                    case 1: {
                      const v_m = __s[1];
                      const __t0 = [0];
                      const __t1 = v_m;
                      v__fn = __t0;
                      v__arg_0 = __t1;
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

function v_evenInt(v_n){
  return (v__scc_evenInt_oddInt)([0], v_n);
}

function v_oddInt(v_n){
  return (v__scc_evenInt_oddInt)([1], v_n);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();