"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [0, [882564211, [0]]]; if (p < -2147483648) return [0, [3768445577, [0]]]; return [1, p|0]; }

function v_threeAndDouble(v_n){
    {
      const __s = __mulInt32(v_n, (2|0));
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [0, v_n, v_n];
        }
        case 1: {
          const v_d = __s[1];
          return [0, v_n, v_d];
        }
      }
    }
}

function v_show(v_pair){
    {
      const __s = v_pair;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          {
            const __s = [1, ("[" + String(v_a))];
            switch (__s[0]) {
              case 0: {
                const v__do_e_13_9 = __s[1];
                return [0, v__do_e_13_9];
              }
              case 1: {
                const v_s0 = __s[1];
                {
                  const __s = [1, (v_s0 + ", ")];
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_14_9 = __s[1];
                      return [0, v__do_e_14_9];
                    }
                    case 1: {
                      const v_s1 = __s[1];
                      {
                        const __s = [1, (v_s1 + String(v_b))];
                        switch (__s[0]) {
                          case 0: {
                            const v__do_e_15_9 = __s[1];
                            return [0, v__do_e_15_9];
                          }
                          case 1: {
                            const v_s2 = __s[1];
                            return [1, (v_s2 + "]")];
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

function main(v__input){
    return (v__let_1)((v_show)((v_threeAndDouble)((5|0))));
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