"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_minUInt8 = (0 & 0xFF);

const v_maxUInt8 = (255 & 0xFF);

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_7_9 = s[1]; return [0, v__do_e_7_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_8_9 = s[1]; return [0, v__do_e_8_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_9_9 = s[1]; return [0, v__do_e_9_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_10_9 = s[1]; return [0, v__do_e_10_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_11_9 = s[1]; return [0, v__do_e_11_9]; } case 1: { const v_s4 = s[1]; return [1, (v_s4 + String(v_maxUInt8))]; } } })([1, (v_s3 + ", ")]); } } })([1, (v_s2 + String((200 & 0xFF)))]); } } })([1, (v_s1 + ", ")]); } } })([1, (v_s0 + String((42 & 0xFF)))]); } } })([1, (String(v_minUInt8) + ", ")]));
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