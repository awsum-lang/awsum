"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_zero = (0|0);

function v_both(v_a, v_b){
    return (v__df_apply_0)(v_zero, v_a, v_b);
}

function v_bothBody(v_a, v_b){
    {
      const __s = [1, (String(v_a) + "/")];
      switch (__s[0]) {
        case 0: {
          const v__do_e_15_3 = __s[1];
          return [0, v__do_e_15_3];
        }
        case 1: {
          const v_s0 = __s[1];
          return [1, (v_s0 + String(v_b))];
        }
      }
    }
}

function main(v__input){
    return (v__let_2)((v_both)((11|0), (22|0)));
}

function v__lam_1(v_a, v_b, v__n){
    return (v_bothBody)(v_a, v_b);
}

function v__let_2(v_res){
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

function v__df_apply_0(v_x, v__df_apply_0_cap0_0, v__df_apply_0_cap0_1){
    return (v__lam_1)(v__df_apply_0_cap0_0, v__df_apply_0_cap0_1, v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();