"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_incr(v_n){
    return v_n;
}

function main(v__input){
    return __print(String((v__df_applyTwice_0)((7|0))));
}

function v__df_apply_1(v_x){
    return (v_incr)(v_x);
}

function v__df_applyTwice_0(v_x){
    return (v__df_apply_1)((v__df_apply_1)(v_x));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();