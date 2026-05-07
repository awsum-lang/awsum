"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }
function __parseInt32(s){ if (!/^-?[0-9]+$/.test(s)) return [0, [0]]; const n = Number(s); if (n < -2147483648 || n > 2147483647) return [0, [0]]; return [1, n | 0]; }

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

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [1, "err"];
        }
        case 1: {
          const v_v = __s[1];
          return __concat("ok:", String(v_v));
        }
      }
    }
}

function main(v__input){
    return (v__let_2)(((s) => { switch(s[0]) { case 0: { const v__do_e_12_9 = s[1]; return [0, v__do_e_12_9]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_13_9 = s[1]; return [0, v__do_e_13_9]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_14_9 = s[1]; return [0, v__do_e_14_9]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_15_9 = s[1]; return [0, v__do_e_15_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_16_9 = s[1]; return [0, v__do_e_16_9]; } case 1: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_17_9 = s[1]; return [0, v__do_e_17_9]; } case 1: { const v_f = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_18_9 = s[1]; return [0, v__do_e_18_9]; } case 1: { const v_g = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_9 = s[1]; return [0, v__do_e_19_9]; } case 1: { const v_h = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_i = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_9 = s[1]; return [0, v__do_e_21_9]; } case 1: { const v_j = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_9 = s[1]; return [0, v__do_e_22_9]; } case 1: { const v_k = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_9 = s[1]; return [0, v__do_e_23_9]; } case 1: { const v_l = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_9 = s[1]; return [0, v__do_e_24_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_25_9 = s[1]; return [0, v__do_e_25_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_26_9 = s[1]; return [0, v__do_e_26_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_27_9 = s[1]; return [0, v__do_e_27_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_28_9 = s[1]; return [0, v__do_e_28_9]; } case 1: { const v_s4 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_29_9 = s[1]; return [0, v__do_e_29_9]; } case 1: { const v_s5 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_30_9 = s[1]; return [0, v__do_e_30_9]; } case 1: { const v_s6 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_31_9 = s[1]; return [0, v__do_e_31_9]; } case 1: { const v_s7 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_32_9 = s[1]; return [0, v__do_e_32_9]; } case 1: { const v_s8 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_33_9 = s[1]; return [0, v__do_e_33_9]; } case 1: { const v_s9 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_34_9 = s[1]; return [0, v__do_e_34_9]; } case 1: { const v_s10 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_35_9 = s[1]; return [0, v__do_e_35_9]; } case 1: { const v_s11 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_36_9 = s[1]; return [0, v__do_e_36_9]; } case 1: { const v_s12 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_37_9 = s[1]; return [0, v__do_e_37_9]; } case 1: { const v_s13 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_38_9 = s[1]; return [0, v__do_e_38_9]; } case 1: { const v_s14 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_39_9 = s[1]; return [0, v__do_e_39_9]; } case 1: { const v_s15 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_40_9 = s[1]; return [0, v__do_e_40_9]; } case 1: { const v_s16 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_41_9 = s[1]; return [0, v__do_e_41_9]; } case 1: { const v_s17 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_42_9 = s[1]; return [0, v__do_e_42_9]; } case 1: { const v_s18 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_43_9 = s[1]; return [0, v__do_e_43_9]; } case 1: { const v_s19 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_44_9 = s[1]; return [0, v__do_e_44_9]; } case 1: { const v_s20 = s[1]; return __concat(v_s20, v_l); } } })(__concat(v_s19, ", ")); } } })(__concat(v_s18, v_k)); } } })(__concat(v_s17, ", ")); } } })(__concat(v_s16, v_j)); } } })(__concat(v_s15, ", ")); } } })(__concat(v_s14, v_i)); } } })(__concat(v_s13, ", ")); } } })(__concat(v_s12, v_h)); } } })(__concat(v_s11, ", ")); } } })(__concat(v_s10, v_g)); } } })(__concat(v_s9, ", ")); } } })(__concat(v_s8, v_f)); } } })(__concat(v_s7, ", ")); } } })(__concat(v_s6, v_e)); } } })(__concat(v_s5, ", ")); } } })(__concat(v_s4, v_d)); } } })(__concat(v_s3, ", ")); } } })(__concat(v_s2, v_c)); } } })(__concat(v_s1, ", ")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, ", ")); } } })((v_render)(__parseInt32("12abc"))); } } })((v_render)(__parseInt32(" 42"))); } } })((v_render)(__parseInt32("+42"))); } } })((v_render)(__parseInt32("-"))); } } })((v_render)(__parseInt32(""))); } } })((v_render)(__parseInt32("-2147483649"))); } } })((v_render)(__parseInt32("2147483648"))); } } })((v_render)(__parseInt32("-2147483648"))); } } })((v_render)(__parseInt32("2147483647"))); } } })((v_render)(__parseInt32("0"))); } } })((v_render)(__parseInt32("-42"))); } } })((v_render)(__parseInt32("42"))));
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