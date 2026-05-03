"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_show(v_c){
    {
      const __s = v_c;
      switch (__s[0]) {
        case 0: {
          return "Red";
        }
        case 1: {
          return "Green";
        }
        case 2: {
          return "Blue";
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_15_9 = s[1]; return [0, v__do_e_15_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_16_9 = s[1]; return [0, v__do_e_16_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_17_9 = s[1]; return [0, v__do_e_17_9]; } case 1: { const v_s2 = s[1]; return [1, (v_s2 + (v_show)([2]))]; } } })([1, (v_s1 + ", ")]); } } })([1, (v_s0 + (v_show)([1]))]); } } })([1, ((v_show)([0]) + ", ")]));
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