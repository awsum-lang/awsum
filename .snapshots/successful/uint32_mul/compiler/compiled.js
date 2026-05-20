"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [16]] : [4, a + b]; }
function __mulUInt32(a, b){ const p = BigInt(a) * BigInt(b); return p > 4294967295n ? [3, [15]] : [4, (Number(p) >>> 0)]; }

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

function v_showOverflowError(v__wild0){
    return "OverflowError";
}

const v_minUInt32 = (0 >>> 0);

const v_maxUInt32 = (4294967295 >>> 0);

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return __concat("overflow: ", (v_showOverflowError)(v_e));
        }
        case 4: {
          const v_v = __s[1];
          return __concat("ok: ", String(v_v));
        }
      }
    }
}

const main = (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_14 = s[1]; return [3, v__do_e_14]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_13 = s[1]; return [3, v__do_e_13]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_12 = s[1]; return [3, v__do_e_12]; } case 4: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_11 = s[1]; return [3, v__do_e_11]; } case 4: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_10 = s[1]; return [3, v__do_e_10]; } case 4: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_9 = s[1]; return [3, v__do_e_9]; } case 4: { const v_f = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_8 = s[1]; return [3, v__do_e_8]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_7 = s[1]; return [3, v__do_e_7]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_6 = s[1]; return [3, v__do_e_6]; } case 4: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_5 = s[1]; return [3, v__do_e_5]; } case 4: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_4 = s[1]; return [3, v__do_e_4]; } case 4: { const v_s4 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_s5 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_2 = s[1]; return [3, v__do_e_2]; } case 4: { const v_s6 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, v__do_e_1]; } case 4: { const v_s7 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, v__do_e_0]; } case 4: { const v_s8 = s[1]; return __concat(v_s8, v_f); } } })(__concat(v_s7, ", ")); } } })(__concat(v_s6, v_e)); } } })(__concat(v_s5, ", ")); } } })(__concat(v_s4, v_d)); } } })(__concat(v_s3, ", ")); } } })(__concat(v_s2, v_c)); } } })(__concat(v_s1, ", ")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, ", ")); } } })((v_render)(__mulUInt32((2 >>> 0), (2147483648 >>> 0)))); } } })((v_render)(__mulUInt32((1 >>> 0), (2147483648 >>> 0)))); } } })((v_render)(__mulUInt32(v_minUInt32, v_maxUInt32))); } } })((v_render)(__mulUInt32(v_maxUInt32, v_maxUInt32))); } } })((v_render)(__mulUInt32((65536 >>> 0), (65536 >>> 0)))); } } })((v_render)(__mulUInt32((65535 >>> 0), (65537 >>> 0)))));

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