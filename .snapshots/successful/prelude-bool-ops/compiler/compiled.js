"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_not(v_b){
  return ((s) => { switch(s[0]) { case 0: { return [1]; } case 1: { return [0]; } } })(v_b);
}

function v_and(v_a, v_b){
  return ((s) => { switch(s[0]) { case 0: { return v_b; } case 1: { return [1]; } } })(v_a);
}

function v_or(v_a, v_b){
  return ((s) => { switch(s[0]) { case 0: { return [0]; } case 1: { return v_b; } } })(v_a);
}

function v_showBool(v_b){
  return ((s) => { switch(s[0]) { case 0: { return "T"; } case 1: { return "F"; } } })(v_b);
}

function main(v__input){
  return __print(((((((v_showBool)((v_not)([0])) + (v_showBool)((v_not)([1]))) + (v_showBool)((v_and)([0], [1]))) + (v_showBool)((v_and)([0], [0]))) + (v_showBool)((v_or)([1], [1]))) + (v_showBool)((v_or)([0], [1]))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();