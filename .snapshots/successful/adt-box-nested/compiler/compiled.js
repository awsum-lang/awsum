"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_b){
  return ((s) => { switch(s[0]) { case 0: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v___p0_p0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v_value = s[1]; return v_value; } } })(v___p0_p0); } } })(v___p0); } } })(v_b);
}

function main(v_input){
  return __print((v_unwrap)([0, [0, [0, "hello"]]]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
