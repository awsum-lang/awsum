"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_pad(v_s){
    return (v__let_1)(("[" + v_s));
}

function main(v__input){
    return __print((v__let_2)((("<" + (v_pad)("hi")) + ">")));
}

function v__let_0(v_q){
    return (v_q + v_q);
}

function v__let_1(v_p){
    return (v__let_0)((v_p + "]"));
}

function v__let_2(v_body){
    return v_body;
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();