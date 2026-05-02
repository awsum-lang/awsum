"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showTri(v_t){
    {
      const __s = v_t;
      switch (__s[0]) {
        case 0: {
          return "A";
        }
        case 1: {
          return "B";
        }
        case 2: {
          return "C";
        }
      }
    }
}

function v_threeTypes(v_n, v_s, v_b){
    return (v__df__let_1_0)(v_b, v_n, v_s);
}

function main(v__input){
    return __print((v_threeTypes)((42|0), "hello", [0]));
}

function v__lam_0(v_x){
    return v_x;
}

function v__df__let_1_0(v_b, v_n, v_s){
    return ((((String((v__lam_0)(v_n)) + "/") + (v__lam_0)(v_s)) + "/") + (v_showTri)((v__lam_0)(v_b)));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();