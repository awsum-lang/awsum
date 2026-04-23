"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_wrap(v_s){
  return [0, v_s];
}

function v_unwrap(v_b){
  return ((s) => { switch(s[0]) { case 0: { const v_value = s[1]; return v_value; } } })(v_b);
}

function v_apply(v_f, v_x){
  return (v_f)(v_x);
}

function v_compose(v_f, v_g, v_x){
  return (v_f)((v_g)(v_x));
}

function main(v__input){
  return __print((v_apply)(v__pap_0, "chain"));
}

function v__pap_0(v__eta0){
  return (v_compose)(v_unwrap, v_wrap, v__eta0);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();