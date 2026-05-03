"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_greeting(v__wild0){
    return "hi";
}

function v_unwrapBox(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return "unwrapped";
        }
      }
    }
}

function v_unwrapBoxNamed(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v__v = __s[1];
          return "unwrapped-named";
        }
      }
    }
}

function v_showPair(v_p){
    {
      const __s = v_p;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          const v___w1 = __s[2];
          return "paired";
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_26_9 = s[1]; return [0, v__do_e_26_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_27_9 = s[1]; return [0, v__do_e_27_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_28_9 = s[1]; return [0, v__do_e_28_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_29_9 = s[1]; return [0, v__do_e_29_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_30_9 = s[1]; return [0, v__do_e_30_9]; } case 1: { const v_s4 = s[1]; return [1, (v_s4 + (v_showPair)([0, "l", "r"]))]; } } })([1, (v_s3 + " ")]); } } })([1, (v_s2 + (v_unwrapBoxNamed)([0, "b"]))]); } } })([1, (v_s1 + " ")]); } } })([1, (v_s0 + (v_unwrapBox)([0, "a"]))]); } } })([1, ((v_greeting)("x") + " ")]));
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