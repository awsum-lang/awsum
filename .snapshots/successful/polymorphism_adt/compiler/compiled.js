"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_identity(v_x){
    return v_x;
}

function main(v__input){
    return __print(((s) => { switch(s[0]) { case 0: { const v_v = s[1]; return v_v; } } })((v_identity)([0, "one"])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();