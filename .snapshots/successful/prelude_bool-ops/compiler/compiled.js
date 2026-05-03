"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_not(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          return [1];
        }
        case 1: {
          return [0];
        }
      }
    }
}

function v_and(v_a, v_b){
    {
      const __s = v_a;
      switch (__s[0]) {
        case 0: {
          return v_b;
        }
        case 1: {
          return [1];
        }
      }
    }
}

function v_or(v_a, v_b){
    {
      const __s = v_a;
      switch (__s[0]) {
        case 0: {
          return [0];
        }
        case 1: {
          return v_b;
        }
      }
    }
}

function v_showBool(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          return "T";
        }
        case 1: {
          return "F";
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_12_9 = s[1]; return [0, v__do_e_12_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_13_9 = s[1]; return [0, v__do_e_13_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_14_9 = s[1]; return [0, v__do_e_14_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_15_9 = s[1]; return [0, v__do_e_15_9]; } case 1: { const v_s3 = s[1]; return [1, (v_s3 + (v_showBool)((v_or)([0], [1])))]; } } })([1, (v_s2 + (v_showBool)((v_or)([1], [1])))]); } } })([1, (v_s1 + (v_showBool)((v_and)([0], [0])))]); } } })([1, (v_s0 + (v_showBool)((v_and)([0], [1])))]); } } })([1, ((v_showBool)((v_not)([0])) + (v_showBool)((v_not)([1])))]));
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