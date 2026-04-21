"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_box){
  return ((s) => { switch(s[0]) { case 0: { const v_value = s[1]; return v_value; } } })(v_box);
}

function v_showResult(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v_a = s[1]; return v_a; } case 1: { const v_e = s[1]; return v_e; } } })(v_r);
}

function main(v__input){
  return __print((((v_unwrap)([0, "from box"]) + " ") + (v_showResult)((v_unwrap)([0, [0, "nested"]]))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
