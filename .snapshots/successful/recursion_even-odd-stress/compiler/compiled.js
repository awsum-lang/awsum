"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [0] : [1]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

function v_showBool(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          return "True";
        }
        case 1: {
          return "False";
        }
      }
    }
}

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

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

function v_showResult(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return __concat("left: ", (v_showUnderflowError)(v_e));
        }
        case 1: {
          const v_b = __s[1];
          return __concat("right: ", (v_showBool)(v_b));
        }
      }
    }
}

function main(v__input){
    return (v__let_2)((v_showResult)((v_evenInt)((1000000|0))));
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

function v__scc_evenInt_oddInt(v__args){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v_n = __s[1];
          {
            const __s = __eqInt32(v_n, (0|0));
            switch (__s[0]) {
              case 0: {
                return [1, [0]];
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
                      const __t0 = [1, v_m];
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
          {
            const __s = __eqInt32(v_n, (0|0));
            switch (__s[0]) {
              case 0: {
                return [1, [1]];
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

function v_evenInt(v_n){
    return (v__scc_evenInt_oddInt)([0, v_n]);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();