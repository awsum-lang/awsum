"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __eqInt32(a, b){ return a === b ? [0] : [1]; }

function v_render(v_b){
  return ((s) => { switch(s[0]) { case 0: { return "T"; } case 1: { return "F"; } } })(v_b);
}

const v_minInt32 = (-2147483648|0);

function main(v__input){
  return __print(((((v_render)(__eqInt32((42|0), (42|0))) + (v_render)(__eqInt32((42|0), (7|0)))) + (v_render)(__eqInt32(v_minInt32, v_minInt32))) + (v_render)(__eqInt32((0|0), (1|0)))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();