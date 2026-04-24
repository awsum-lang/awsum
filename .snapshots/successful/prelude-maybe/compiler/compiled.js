"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_m){
  return ((s) => { switch(s[0]) { case 0: { return "nothing"; } case 1: { const v_s = s[1]; return ("just: " + v_s); } } })(v_m);
}

function main(v__input){
  return __print((((v_unwrap)([1, "hi"]) + ", ") + (v_unwrap)([0])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();