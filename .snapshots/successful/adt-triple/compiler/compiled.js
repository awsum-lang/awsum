"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showTriple(v_t){
  return ((s) => { switch(s[0]) { case 0: { const v_a = s[1]; const v_b = s[2]; const v_c = s[3]; return ((((v_a + " ") + v_b) + " ") + v_c); } } })(v_t);
}

function main(v_input){
  return __print((v_showTriple)([0, "one", "two", "three"]));
}

function v__con_Triple(v__x0, v__x1, v__x2){
  return [0, v__x0, v__x1, v__x2];
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
