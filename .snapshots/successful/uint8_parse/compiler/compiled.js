"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [16]] : [4, a + b]; }
function __parseUInt8(s){ if (!/^[0-9]+$/.test(s)) return [3, [18]]; const n = Number(s); if (n > 255) return [3, [18]]; return [4, n & 0xFF]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_u = __s[1];
          return v_u;
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = null;
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
        case 3: {
          const v___w0 = __s[1];
          return [4, "err"];
        }
        case 4: {
          const v_v = __s[1];
          return __concat("ok:", String(v_v));
        }
      }
    }
}

const main = (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_13_9 = s[1]; return [3, v__do_e_13_9]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_14_9 = s[1]; return [3, v__do_e_14_9]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_15_9 = s[1]; return [3, v__do_e_15_9]; } case 4: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_16_9 = s[1]; return [3, v__do_e_16_9]; } case 4: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_17_9 = s[1]; return [3, v__do_e_17_9]; } case 4: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_18_9 = s[1]; return [3, v__do_e_18_9]; } case 4: { const v_f = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_19_9 = s[1]; return [3, v__do_e_19_9]; } case 4: { const v_g = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_20_9 = s[1]; return [3, v__do_e_20_9]; } case 4: { const v_h = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_21_9 = s[1]; return [3, v__do_e_21_9]; } case 4: { const v_r0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_22_9 = s[1]; return [3, v__do_e_22_9]; } case 4: { const v_r1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_23_9 = s[1]; return [3, v__do_e_23_9]; } case 4: { const v_r2 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_24_9 = s[1]; return [3, v__do_e_24_9]; } case 4: { const v_r3 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_25_9 = s[1]; return [3, v__do_e_25_9]; } case 4: { const v_r4 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_26_9 = s[1]; return [3, v__do_e_26_9]; } case 4: { const v_r5 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_27_9 = s[1]; return [3, v__do_e_27_9]; } case 4: { const v_r6 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_28_9 = s[1]; return [3, v__do_e_28_9]; } case 4: { const v_r7 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_29_9 = s[1]; return [3, v__do_e_29_9]; } case 4: { const v_r8 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_30_9 = s[1]; return [3, v__do_e_30_9]; } case 4: { const v_r9 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_31_9 = s[1]; return [3, v__do_e_31_9]; } case 4: { const v_r10 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_32_9 = s[1]; return [3, v__do_e_32_9]; } case 4: { const v_r11 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_33_9 = s[1]; return [3, v__do_e_33_9]; } case 4: { const v_r12 = s[1]; return __concat(v_r12, v_h); } } })(__concat(v_r11, ", ")); } } })(__concat(v_r10, v_g)); } } })(__concat(v_r9, ", ")); } } })(__concat(v_r8, v_f)); } } })(__concat(v_r7, ", ")); } } })(__concat(v_r6, v_e)); } } })(__concat(v_r5, ", ")); } } })(__concat(v_r4, v_d)); } } })(__concat(v_r3, ", ")); } } })(__concat(v_r2, v_c)); } } })(__concat(v_r1, ", ")); } } })(__concat(v_r0, v_b)); } } })(__concat(v_a, ", ")); } } })((v_render)(__parseUInt8("12a"))); } } })((v_render)(__parseUInt8(" 5"))); } } })((v_render)(__parseUInt8("abc"))); } } })((v_render)(__parseUInt8(""))); } } })((v_render)(__parseUInt8("-1"))); } } })((v_render)(__parseUInt8("256"))); } } })((v_render)(__parseUInt8("255"))); } } })((v_render)(__parseUInt8("0"))));

function v__let_12(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();