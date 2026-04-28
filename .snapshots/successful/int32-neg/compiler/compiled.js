"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __negInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((-x)|0)]; }

function v_showOverflowError(v__wild0){
  return "OverflowError";
}

function v_render(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_e = s[1]; return ("overflow: " + (v_showOverflowError)(v_e)); } case 1: { const v_v = s[1]; return ("ok: " + String(v_v)); } } })(v_r);
}

const v_maxInt32 = (2147483647|0);

const v_minInt32 = (-2147483648|0);

function main(v__input){
  return __print((((((((((v_render)(__negInt32((5|0))) + ", ") + (v_render)(__negInt32((-5|0)))) + ", ") + (v_render)(__negInt32((0|0)))) + ", ") + (v_render)(__negInt32(v_maxInt32))) + ", ") + (v_render)(__negInt32(v_minInt32))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();