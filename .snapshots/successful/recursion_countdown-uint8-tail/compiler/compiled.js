"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predUInt8(x){ return x === 0 ? [0, [0]] : [1, ((x - 1) & 0xFF)]; }
function __eqUInt8(a, b){ return a === b ? [0] : [1]; }

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

function v_countDown(v_n, v_acc){
  while (true) {
    {
      const __s = __eqUInt8(v_n, (0 & 0xFF));
      switch (__s[0]) {
        case 0: {
          return [1, (v_acc + String(v_n))];
        }
        case 1: {
          {
            const __s = __predUInt8(v_n);
            switch (__s[0]) {
              case 0: {
                const v_e = __s[1];
                return [0, [3768445577, v_e]];
              }
              case 1: {
                const v_m = __s[1];
                {
                  const __s = [1, (v_acc + String(v_n))];
                  switch (__s[0]) {
                    case 0: {
                      const v_e = __s[1];
                      return [0, [3768445577, v_e]];
                    }
                    case 1: {
                      const v_s0 = __s[1];
                      {
                        const __s = [1, (v_s0 + ",")];
                        switch (__s[0]) {
                          case 0: {
                            const v_e = __s[1];
                            return [0, [3768445577, v_e]];
                          }
                          case 1: {
                            const v_s1 = __s[1];
                            const __t0 = v_m;
                            const __t1 = v_s1;
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
          {
            const __s = v_e;
            switch (__s[0]) {
              case 589989748: {
                const v___rw = __s[1];
                return [1, "STRING_TOO_LONG"];
              }
              case 3768445577: {
                const v_u = __s[1];
                return [1, ("left: " + (v_showUnderflowError)(v_u))];
              }
            }
          }
        }
        case 1: {
          const v_s = __s[1];
          return [1, ("right: " + v_s)];
        }
      }
    }
}

function main(v__input){
    return (v__let_1)((v_showResult)((v_countDown)((255 & 0xFF), "")));
}

function v__let_1(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("STRING_TOO_LONG");
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();