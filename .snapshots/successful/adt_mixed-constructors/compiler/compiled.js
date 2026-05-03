"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showToken(v_token){
    {
      const __s = v_token;
      switch (__s[0]) {
        case 0: {
          const v_w = __s[1];
          return [1, ("word:" + v_w)];
        }
        case 1: {
          const v_n = __s[1];
          return [1, ("num:" + v_n)];
        }
        case 2: {
          return [1, ","];
        }
        case 3: {
          return [1, "<eof>"];
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_16_9 = s[1]; return [0, v__do_e_16_9]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_17_9 = s[1]; return [0, v__do_e_17_9]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_18_9 = s[1]; return [0, v__do_e_18_9]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_9 = s[1]; return [0, v__do_e_19_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_ab = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_9 = s[1]; return [0, v__do_e_21_9]; } case 1: { const v_abc = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_9 = s[1]; return [0, v__do_e_22_9]; } case 1: { const v_abcs = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_9 = s[1]; return [0, v__do_e_23_9]; } case 1: { const v_abcsc = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_9 = s[1]; return [0, v__do_e_24_9]; } case 1: { const v_abcscd = s[1]; return [1, (v_abcscd + v_d)]; } } })([1, (v_abcsc + " ")]); } } })([1, (v_abcs + v_c)]); } } })([1, (v_abc + " ")]); } } })([1, (v_ab + v_b)]); } } })([1, (v_a + " ")]); } } })((v_showToken)([3])); } } })((v_showToken)([1, "42"])); } } })((v_showToken)([2])); } } })((v_showToken)([0, "hello"])));
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