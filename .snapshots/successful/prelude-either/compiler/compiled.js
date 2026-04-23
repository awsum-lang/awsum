"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_e = s[1]; return ("left: " + v_e); } case 1: { const v_v = s[1]; return ("right: " + v_v); } } })(v_r);
}

function main(v__input){
  return __print((((v_unwrap)([0, "bad"]) + ", ") + (v_unwrap)([1, "good"])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();