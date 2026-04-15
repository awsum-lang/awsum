"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_search(v_key){
  return [0, ("found:" + v_key)];
}

function main(v_input){
  return __print(((s) => { switch(s[0]) { case 0: { const v_v = s[1]; return v_v; } case 1: { return "nothing"; } } })((v_search)("hello")));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
