"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [0, [882564211, [0]]]; if (p < -2147483648) return [0, [3768445577, [0]]]; return [1, p|0]; }

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

function v_showOverflowError(v__wild0){
    return "OverflowError";
}

const v_minInt32 = (-2147483648|0);

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 882564211: {
                const v_o = __s[1];
                return [1, ("err: " + (v_showOverflowError)(v_o))];
              }
              case 3768445577: {
                const v_u = __s[1];
                return [1, ("err: " + (v_showUnderflowError)(v_u))];
              }
            }
          }
        }
        case 1: {
          const v_v = __s[1];
          return [1, ("ok: " + String(v_v))];
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_14_9 = s[1]; return [0, v__do_e_14_9]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_15_9 = s[1]; return [0, v__do_e_15_9]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_16_9 = s[1]; return [0, v__do_e_16_9]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_17_9 = s[1]; return [0, v__do_e_17_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_18_9 = s[1]; return [0, v__do_e_18_9]; } case 1: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_9 = s[1]; return [0, v__do_e_19_9]; } case 1: { const v_f = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_9 = s[1]; return [0, v__do_e_21_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_9 = s[1]; return [0, v__do_e_22_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_9 = s[1]; return [0, v__do_e_23_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_9 = s[1]; return [0, v__do_e_24_9]; } case 1: { const v_s4 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_25_9 = s[1]; return [0, v__do_e_25_9]; } case 1: { const v_s5 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_26_9 = s[1]; return [0, v__do_e_26_9]; } case 1: { const v_s6 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_27_9 = s[1]; return [0, v__do_e_27_9]; } case 1: { const v_s7 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_28_9 = s[1]; return [0, v__do_e_28_9]; } case 1: { const v_s8 = s[1]; return [1, (v_s8 + v_f)]; } } })([1, (v_s7 + ", ")]); } } })([1, (v_s6 + v_e)]); } } })([1, (v_s5 + ", ")]); } } })([1, (v_s4 + v_d)]); } } })([1, (v_s3 + ", ")]); } } })([1, (v_s2 + v_c)]); } } })([1, (v_s1 + ", ")]); } } })([1, (v_s0 + v_b)]); } } })([1, (v_a + ", ")]); } } })((v_render)(__mulInt32(v_minInt32, (1|0)))); } } })((v_render)(__mulInt32(v_minInt32, (-1|0)))); } } })((v_render)(__mulInt32((-100000|0), (100000|0)))); } } })((v_render)(__mulInt32((100000|0), (100000|0)))); } } })((v_render)(__mulInt32((-6|0), (7|0)))); } } })((v_render)(__mulInt32((6|0), (7|0)))));
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