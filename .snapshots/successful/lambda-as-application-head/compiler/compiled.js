"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_runMe = (v__lam_0)((5|0));

const v_doubled = (v__lam_1)(v_runMe);

function main(v__input){
    return __print(String(v_doubled));
}

function v__lam_0(v_x){
    return v_x;
}

function v__lam_1(v_n){
    return v_n;
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();