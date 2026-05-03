"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_search(v_key){
    {
      const __s = [1, ("found:" + v_key)];
      switch (__s[0]) {
        case 0: {
          const v__do_e_8_3 = __s[1];
          return [0, v__do_e_8_3];
        }
        case 1: {
          const v_found = __s[1];
          return [1, [0, v_found]];
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v_e = s[1]; return [0, v_e]; } case 1: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v_v = s[1]; return [1, v_v]; } case 1: { return [1, "nothing"]; } } })(v___p0); } } })((v_search)("hello")));
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