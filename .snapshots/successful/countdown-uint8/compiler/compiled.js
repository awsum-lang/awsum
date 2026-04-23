"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predUInt8(x){ return x === 0 ? [0, [0]] : [1, ((x - 1) & 0xFF)]; }

function v_countDown(v_n){
  return ((s) => { switch(s[0]) { case 0: { const v___w0 = s[1]; return String(v_n); } case 1: { const v_m = s[1]; return ((String(v_n) + ",") + (v_countDown)(v_m)); } } })(__predUInt8(v_n));
}

function main(v__input){
  return __print((v_countDown)((255 & 0xFF)));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();