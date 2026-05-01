"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [882564211, [0]]]; if (s < -2147483648) return [0, [3768445577, [0]]]; return [1, s|0]; }

function v_sumTriple(v__arg_21_11){
    {
      const __s = v__arg_21_11;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          const v_c = __s[3];
          {
            const __s = __addInt32(v_a, v_b);
            switch (__s[0]) {
              case 0: {
                const v___w0 = __s[1];
                return (0|0);
              }
              case 1: {
                const v_ab = __s[1];
                {
                  const __s = __addInt32(v_ab, v_c);
                  switch (__s[0]) {
                    case 0: {
                      const v___w0 = __s[1];
                      return (0|0);
                    }
                    case 1: {
                      const v_abc = __s[1];
                      return v_abc;
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

function v_sumPair(v__arg_31_9){
    {
      const __s = v__arg_31_9;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          {
            const __s = __addInt32(v_a, v_b);
            switch (__s[0]) {
              case 0: {
                const v___w0 = __s[1];
                return (0|0);
              }
              case 1: {
                const v_s = __s[1];
                return v_s;
              }
            }
          }
        }
      }
    }
}

const v_triple = [0, (10|0), (20|0), (30|0)];

const v_pair = [0, (100|0), (200|0)];

function main(v__input){
    return (v__let_2)((v_sumTriple)(v_triple));
}

function v__lam_0(v__arg_44_19){
    {
      const __s = v__arg_44_19;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          return (v_sumPair)([0, v_a, v_b]);
        }
      }
    }
}

function v__let_1(v_n, v_m){
    return __print(((String(v_n) + " / ") + String(v_m)));
}

function v__let_2(v_n){
    return (v__let_1)(v_n, (v__df_apply_0)(v_pair));
}

function v__df_apply_0(v_t){
    return (v__lam_0)(v_t);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();