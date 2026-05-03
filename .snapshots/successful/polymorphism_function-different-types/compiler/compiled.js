"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_box){
    {
      const __s = v_box;
      switch (__s[0]) {
        case 0: {
          const v_value = __s[1];
          return v_value;
        }
      }
    }
}

function v_showResult(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          return v_a;
        }
        case 1: {
          const v_e = __s[1];
          return v_e;
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_s0 = s[1]; return [1, (v_s0 + (v_showResult)((v_unwrap)([0, [0, "nested"]])))]; } } })([1, ((v_unwrap)([0, "from box"]) + " ")]));
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