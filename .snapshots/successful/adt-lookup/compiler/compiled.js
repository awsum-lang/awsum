"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_x){
  return ((s) => { switch(s[0]) { case 0: { const v_value = s[1]; return v_value; } case 1: { return "not found"; } } })(v_x);
}

function main(v__input){
  return __print((((v_unwrap)([0, "hello"]) + ", ") + (v_unwrap)([1])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
