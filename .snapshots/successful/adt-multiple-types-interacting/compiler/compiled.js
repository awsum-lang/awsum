"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_colorName(v_c){
  return ((s) => { switch(s[0]) { case 0: { return "red"; } case 1: { return "green"; } case 2: { return "blue"; } } })(v_c);
}

function v_showBoxedColor(v_bc){
  return ((s) => { switch(s[0]) { case 0: { const v_c = s[1]; return (v_colorName)(v_c); } } })(v_bc);
}

function v_showResult(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_box = s[1]; return (v_showBoxedColor)(v_box); } case 1: { const v_e = s[1]; return v_e; } } })(v_r);
}

function main(v__input){
  return __print((((v_showBoxedColor)([0, [0]]) + " ") + (v_showResult)([0, [0, [1]]])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();