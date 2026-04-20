"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_r){
  return ((s) => { switch(s[0]) { case 0: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v_value = s[1]; return v_value; } case 1: { const v_value = s[1]; return v_value; } } })(v___p0); } case 1: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v_value = s[1]; return v_value; } case 1: { const v_value = s[1]; return v_value; } } })(v___p0); } } })(v_r);
}

function main(v__input){
  return __print((((((((v_unwrap)([0, [0, "1"]]) + ",") + (v_unwrap)([0, [1, "2"]])) + ",") + (v_unwrap)([1, [0, "3"]])) + ",") + (v_unwrap)([1, [1, "4"]])));
}

function v__con_Err(v__x0){
  return [1, v__x0];
}

function v__con_Ok(v__x0){
  return [0, v__x0];
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
