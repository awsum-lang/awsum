"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_zero = (0|0);

function v_both(v_a, v_b){
    return (v__df_apply_0)(v_zero, v_a, v_b);
}

function main(v__input){
    return __print((v_both)((11|0), (22|0)));
}

function v__lam_0(v_a, v_b, v__n){
    return ((String(v_a) + "/") + String(v_b));
}

function v__df_apply_0(v_x, v__df_apply_0_cap0_0, v__df_apply_0_cap0_1){
    return (v__lam_0)(v__df_apply_0_cap0_0, v__df_apply_0_cap0_1, v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();