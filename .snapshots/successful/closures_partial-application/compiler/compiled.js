"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_wrap(v_s){
    return [0, v_s];
}

function v_unwrap(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v_value = __s[1];
          return v_value;
        }
      }
    }
}

function v_compose(v_f, v_g, v_x){
    return (v_f)((v_g)(v_x));
}

function main(v__input){
    return __print((v__df_apply_0)("chain", v_unwrap, v_wrap));
}

function v__df_apply_0(v_x, v__df_apply_0_cap0_0, v__df_apply_0_cap0_1){
    return (v_compose)(v__df_apply_0_cap0_0, v__df_apply_0_cap0_1, v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();