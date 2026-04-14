"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_show(v_xs){
  return ((s) => { switch(s[0]) { case 0: { const v_h = s[1]; const v_t = s[2]; return ((v_h + ",") + (v_show)(v_t)); } case 1: { return ""; } } })(v_xs);
}

const v_exampleList = [0, "a", [0, "b", [0, "c", [1]]]];

function main(v_input){
  return __print((v_show)(v_exampleList));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
