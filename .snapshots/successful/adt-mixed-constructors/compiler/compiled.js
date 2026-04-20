"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showToken(v_token){
  return ((s) => { switch(s[0]) { case 0: { const v_w = s[1]; return ("word:" + v_w); } case 1: { const v_n = s[1]; return ("num:" + v_n); } case 2: { return ","; } case 3: { return "<eof>"; } } })(v_token);
}

function main(v__input){
  return __print((((((((v_showToken)([0, "hello"]) + " ") + (v_showToken)([2])) + " ") + (v_showToken)([1, "42"])) + " ") + (v_showToken)([3])));
}

function v__con_Number(v__x0){
  return [1, v__x0];
}

function v__con_Word(v__x0){
  return [0, v__x0];
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
