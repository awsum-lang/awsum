"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_map(v_f, v_list){
  return ((s) => { switch(s[0]) { case 0: { const v_head = s[1]; const v_tail = s[2]; return [0, (v_f)(v_head), (v_map)(v_f, v_tail)]; } case 1: { return [1]; } } })(v_list);
}

function v_show(v_xs){
  return ((s) => { switch(s[0]) { case 0: { const v_h = s[1]; const v_t = s[2]; return ((v_h + ",") + (v_show)(v_t)); } case 1: { return ""; } } })(v_xs);
}

function v_shout(v_s){
  return (v_s + "!");
}

function main(v__input){
  return __print((v_show)((v_map)(v_shout, [0, "a", [0, "b", [0, "c", [1]]]])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
