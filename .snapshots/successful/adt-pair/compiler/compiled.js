"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showPair(v_pair){
  return ((s) => { switch(s[0]) { case 0: { const v_first = s[1]; const v_second = s[2]; return (((("(" + v_first) + ", ") + v_second) + ")"); } } })(v_pair);
}

function main(v_input){
  return __print((v_showPair)([0, "hello", "world"]));
}

function v__con_Pair(v__x0, v__x1){
  return [0, v__x0, v__x1];
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
