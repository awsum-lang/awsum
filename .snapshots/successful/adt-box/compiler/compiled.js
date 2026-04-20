"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_b){
  return ((s) => { switch(s[0]) { case 0: { const v_value = s[1]; return v_value; } } })(v_b);
}

function main(v__input){
  return __print((v_unwrap)([0, "hello"]));
}

function v__con_Box(v__x0){
  return [0, v__x0];
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
