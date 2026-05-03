"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showTriple(v_t){
    {
      const __s = v_t;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          const v_c = __s[3];
          return (v_h0)(v_a, v_b, v_c);
        }
      }
    }
}

function main(v__input){
    return (v__let_1)((v_showTriple)([0, "one", "two", "three"]));
}

function v_h0(v_a, v_b, v_c){
    {
      const __s = [1, (v_a + " ")];
      switch (__s[0]) {
        case 0: {
          const v__do_e_20_5 = __s[1];
          return [0, v__do_e_20_5];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = [1, (v_s0 + v_b)];
            switch (__s[0]) {
              case 0: {
                const v__do_e_21_5 = __s[1];
                return [0, v__do_e_21_5];
              }
              case 1: {
                const v_s1 = __s[1];
                {
                  const __s = [1, (v_s1 + " ")];
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_22_5 = __s[1];
                      return [0, v__do_e_22_5];
                    }
                    case 1: {
                      const v_s2 = __s[1];
                      return [1, (v_s2 + v_c)];
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