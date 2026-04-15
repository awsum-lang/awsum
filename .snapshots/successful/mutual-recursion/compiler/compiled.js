"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_handleA(v_step){
  return ((s) => { switch(s[0]) { case 0: { return ("A" + (v_handleB)([1])); } case 1: { return (v_handleB)(v_step); } case 2: { return (v_handleB)(v_step); } case 3: { return ""; } } })(v_step);
}

function v_handleB(v_step){
  return ((s) => { switch(s[0]) { case 0: { return (v_handleA)(v_step); } case 1: { return ("B" + (v_handleA)([2])); } case 2: { return ("C" + (v_handleA)([3])); } case 3: { return ""; } } })(v_step);
}

function main(v_input){
  return __print((v_handleA)([0]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
