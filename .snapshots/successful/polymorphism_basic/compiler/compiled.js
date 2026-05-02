"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_const(v_x, v__y){
    return v_x;
}

function main(v__input){
    return __print((v_identity)((v__df_compose_0)((v_const)("a", "b"))));
}

function v_identity(v_x){
    return v_x;
}

function v_appendX(v_s){
    return (v_s + "x");
}

function v_appendY(v_s){
    return (v_s + "y");
}

function v__df_compose_0(v_x){
    return (v_appendY)((v_appendX)(v_x));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();