"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __subUInt8(a, b){ const d = a - b; return d < 0 ? [0, [0]] : [1, d & 0xFF]; }

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

const v_minUInt8 = (0 & 0xFF);

const v_maxUInt8 = (255 & 0xFF);

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return [1, ("underflow: " + (v_showUnderflowError)(v_e))];
        }
        case 1: {
          const v_v = __s[1];
          return [1, ("ok: " + String(v_v))];
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_12_9 = s[1]; return [0, v__do_e_12_9]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_13_9 = s[1]; return [0, v__do_e_13_9]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_14_9 = s[1]; return [0, v__do_e_14_9]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_15_9 = s[1]; return [0, v__do_e_15_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_16_9 = s[1]; return [0, v__do_e_16_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_17_9 = s[1]; return [0, v__do_e_17_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_18_9 = s[1]; return [0, v__do_e_18_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_9 = s[1]; return [0, v__do_e_19_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_s4 = s[1]; return [1, (v_s4 + v_d)]; } } })([1, (v_s3 + ", ")]); } } })([1, (v_s2 + v_c)]); } } })([1, (v_s1 + ", ")]); } } })([1, (v_s0 + v_b)]); } } })([1, (v_a + ", ")]); } } })((v_render)(__subUInt8(v_minUInt8, v_maxUInt8))); } } })((v_render)(__subUInt8(v_minUInt8, (1 & 0xFF)))); } } })((v_render)(__subUInt8(v_maxUInt8, v_minUInt8))); } } })((v_render)(__subUInt8((5 & 0xFF), (5 & 0xFF)))));
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