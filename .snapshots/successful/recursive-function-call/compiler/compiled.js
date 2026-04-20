"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_advanceStep(v_x){
  return ((s) => { switch(s[0]) { case 0: { return (v_advanceStep)([1]); } case 1: { return (v_advanceStep)([2]); } case 2: { return "Done!"; } } })(v_x);
}

function main(v__input){
  return __print((v_advanceStep)([0]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
