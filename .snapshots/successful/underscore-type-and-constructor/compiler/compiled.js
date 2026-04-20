"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_show(v_x){
  return ((s) => { switch(s[0]) { case 0: { return "one"; } case 1: { return "two"; } } })(v_x);
}

function main(v__input){
  return __print((v_show)([0]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
