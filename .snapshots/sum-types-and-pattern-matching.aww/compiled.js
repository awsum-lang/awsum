"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_show(v_c){
  return ((s) => { switch(s) { case 0: return "Red"; case 1: return "Green"; case 2: return "Blue"; } })(v_c);
}

function main(v_input){
  return __print((((((v_show)(0) + ", ") + (v_show)(1)) + ", ") + (v_show)(2)));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
