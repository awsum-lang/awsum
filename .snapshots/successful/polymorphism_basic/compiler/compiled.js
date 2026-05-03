"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_const(v_x, v__y){
    return v_x;
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_7_9 = s[1]; return [0, v__do_e_7_9]; } case 1: { const v_ax = s[1]; return (v_identity)((v_appendY)(v_ax)); } } })((v_appendX)((v_const)("a", "b"))));
}

function v_identity(v_x){
    return v_x;
}

function v_appendX(v_s){
    return [1, (v_s + "x")];
}

function v_appendY(v_s){
    return [1, (v_s + "y")];
}

function v__let_1(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("STRING_TOO_LONG");
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();