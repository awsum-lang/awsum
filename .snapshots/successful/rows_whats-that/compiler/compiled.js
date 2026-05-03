"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showUnit(v__wild0){
    return "Unit";
}

function v_whatsThat(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1454647603: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 0: {
                return [1, "Nothing"];
              }
              case 1: {
                const v___pa0 = __s[1];
                {
                  const __s = v___pa0;
                  switch (__s[0]) {
                    case 796142685: {
                      const v_b = __s[1];
                      {
                        const __s = v_b;
                        switch (__s[0]) {
                          case 0: {
                            return [1, "Just True"];
                          }
                          case 1: {
                            return [1, "Just False"];
                          }
                        }
                      }
                    }
                    case 1759602215: {
                      const v_u = __s[1];
                      return [1, ("Just " + (v_showUnit)(v_u))];
                    }
                  }
                }
              }
            }
          }
        }
        case 1615808600: {
          const v_s = __s[1];
          return [1, ("String " + v_s)];
        }
        case 2711245919: {
          const v_n = __s[1];
          return [1, ("Int32 " + String(v_n))];
        }
      }
    }
}

function main(v__input){
    return (v__let_1)((v_whatsThat)([1454647603, [1, [796142685, [0]]]]));
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