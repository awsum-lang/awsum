"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showPair(v_pair){
    {
      const __s = v_pair;
      switch (__s[0]) {
        case 0: {
          const v_first = __s[1];
          const v_second = __s[2];
          return (v_showPairBody)(v_first, v_second);
        }
      }
    }
}

function v_showPairBody(v_first, v_second){
    {
      const __s = [1, ("(" + v_first)];
      switch (__s[0]) {
        case 0: {
          const v__do_e_12_3 = __s[1];
          return [0, v__do_e_12_3];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = [1, (v_s0 + ", ")];
            switch (__s[0]) {
              case 0: {
                const v__do_e_13_3 = __s[1];
                return [0, v__do_e_13_3];
              }
              case 1: {
                const v_s1 = __s[1];
                {
                  const __s = [1, (v_s1 + v_second)];
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_14_3 = __s[1];
                      return [0, v__do_e_14_3];
                    }
                    case 1: {
                      const v_s2 = __s[1];
                      return [1, (v_s2 + ")")];
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
    return (v__let_1)((v_showPair)([0, "hello", "world"]));
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