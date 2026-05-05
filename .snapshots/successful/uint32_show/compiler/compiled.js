"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_minUInt32 = (0 >>> 0);

const v_maxUInt32 = (4294967295 >>> 0);

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_7_9 = s[1]; return [0, v__do_e_7_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_8_9 = s[1]; return [0, v__do_e_8_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_9_9 = s[1]; return [0, v__do_e_9_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_10_9 = s[1]; return [0, v__do_e_10_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_11_9 = s[1]; return [0, v__do_e_11_9]; } case 1: { const v_s4 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_12_9 = s[1]; return [0, v__do_e_12_9]; } case 1: { const v_s5 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_13_9 = s[1]; return [0, v__do_e_13_9]; } case 1: { const v_s6 = s[1]; return [1, (v_s6 + String(v_maxUInt32))]; } } })([1, (v_s5 + ", ")]); } } })([1, (v_s4 + String((4000000000 >>> 0)))]); } } })([1, (v_s3 + ", ")]); } } })([1, (v_s2 + String((2147483648 >>> 0)))]); } } })([1, (v_s1 + ", ")]); } } })([1, (v_s0 + String((42 >>> 0)))]); } } })([1, (String(v_minUInt32) + ", ")]));
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