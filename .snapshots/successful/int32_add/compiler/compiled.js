"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [882564211, [0]]]; if (s < -2147483648) return [0, [3768445577, [0]]]; return [1, s|0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

function v_showOverflowError(v__wild0){
    return "OverflowError";
}

const v_minInt32 = (-2147483648|0);

const v_maxInt32 = (2147483647|0);

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
                return __concat("err: ", (v_showOverflowError)(v_o));
              }
              case 3768445577: {
                const v_u = __s[1];
                return __concat("err: ", (v_showUnderflowError)(v_u));
              }
            }
          }
        }
        case 1: {
          const v_v = __s[1];
          return __concat("ok: ", String(v_v));
        }
      }
    }
}

function main(v__input){
    return (v__let_2)(((s) => { switch(s[0]) { case 0: { const v__do_e_14_9 = s[1]; return [0, v__do_e_14_9]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_15_9 = s[1]; return [0, v__do_e_15_9]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_16_9 = s[1]; return [0, v__do_e_16_9]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_17_9 = s[1]; return [0, v__do_e_17_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_18_9 = s[1]; return [0, v__do_e_18_9]; } case 1: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_9 = s[1]; return [0, v__do_e_19_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_9 = s[1]; return [0, v__do_e_21_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_9 = s[1]; return [0, v__do_e_22_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_9 = s[1]; return [0, v__do_e_23_9]; } case 1: { const v_s4 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_9 = s[1]; return [0, v__do_e_24_9]; } case 1: { const v_s5 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_25_9 = s[1]; return [0, v__do_e_25_9]; } case 1: { const v_s6 = s[1]; return __concat(v_s6, v_e); } } })(__concat(v_s5, ", ")); } } })(__concat(v_s4, v_d)); } } })(__concat(v_s3, ", ")); } } })(__concat(v_s2, v_c)); } } })(__concat(v_s1, ", ")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, ", ")); } } })((v_render)(__addInt32(v_maxInt32, v_minInt32))); } } })((v_render)(__addInt32(v_minInt32, (-1|0)))); } } })((v_render)(__addInt32(v_maxInt32, (1|0)))); } } })((v_render)(__addInt32((100|0), (-50|0)))); } } })((v_render)(__addInt32((100|0), (23|0)))));
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();