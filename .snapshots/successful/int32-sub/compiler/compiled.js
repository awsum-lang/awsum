"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __subInt32(a, b){ const d = a - b; if (d > 2147483647) return [0, [1]]; if (d < -2147483648) return [0, [0]]; return [1, d|0]; }

function v_showArithError(v_e){
  return ((s) => { switch(s[0]) { case 0: { return "Underflow"; } case 1: { return "Overflow"; } } })(v_e);
}

function v_render(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_e = s[1]; return ("err: " + (v_showArithError)(v_e)); } case 1: { const v_v = s[1]; return ("ok: " + String(v_v)); } } })(v_r);
}

const v_maxInt32 = (2147483647|0);

const v_minInt32 = (-2147483648|0);

function main(v__input){
  return __print((((((((((v_render)(__subInt32((100|0), (23|0))) + ", ") + (v_render)(__subInt32((100|0), (-50|0)))) + ", ") + (v_render)(__subInt32(v_maxInt32, (-1|0)))) + ", ") + (v_render)(__subInt32(v_minInt32, (1|0)))) + ", ") + (v_render)(__subInt32((0|0), v_minInt32))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();