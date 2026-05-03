"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showTri(v_t){
    {
      const __s = v_t;
      switch (__s[0]) {
        case 0: {
          return "A";
        }
        case 1: {
          return "B";
        }
        case 2: {
          return "C";
        }
      }
    }
}

function v_threeTypes(v_n, v_s, v_b){
    return (v__df__let_2_0)(v_b, v_n, v_s);
}

function main(v__input){
    return (v__let_3)((v_threeTypes)((42|0), "hello", [0]));
}

function v__lam_1(v_x){
    return v_x;
}

function v__let_3(v_res){
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

function v__df__let_2_0(v_b, v_n, v_s){
    {
      const __s = [1, (String((v__lam_1)(v_n)) + "/")];
      switch (__s[0]) {
        case 0: {
          const v__do_e_17_9 = __s[1];
          return [0, v__do_e_17_9];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = [1, (v_s0 + (v__lam_1)(v_s))];
            switch (__s[0]) {
              case 0: {
                const v__do_e_18_9 = __s[1];
                return [0, v__do_e_18_9];
              }
              case 1: {
                const v_s1 = __s[1];
                {
                  const __s = [1, (v_s1 + "/")];
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_19_9 = __s[1];
                      return [0, v__do_e_19_9];
                    }
                    case 1: {
                      const v_s2 = __s[1];
                      return [1, (v_s2 + (v_showTri)((v__lam_1)(v_b)))];
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

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();