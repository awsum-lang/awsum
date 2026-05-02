"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_answer = (42|0);

function v_captureFn(v_k){
    return (v__df_apply_0)(v_answer, v_k);
}

function main(v__input){
    return __print(String((v_captureFn)((7|0))));
}

function v__lam_1(v_k, v__n){
    return v_k;
}

function v__df_apply_0(v_x, v__df_apply_0_cap0_0){
    return (v__lam_1)(v__df_apply_0_cap0_0, v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();