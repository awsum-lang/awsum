"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
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

const v_n = (42|0);

const v_basic = String(v_n);

const v_chained = (v_wrap)((v_wrap)(String(v_n)));

const v_viaLambda = (v__lam_7)(v_n);

function v_wrap(v_s){
    return v_s;
}

const v_joined = ((s) => { switch(s[0]) { case 0: { const v__do_e_28_3 = s[1]; return [0, v__do_e_28_3]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_29_3 = s[1]; return [0, v__do_e_29_3]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_30_3 = s[1]; return [0, v__do_e_30_3]; } case 1: { const v_c = s[1]; return __concat(v_c, v_viaLambda); } } })(__concat(v_b, "|")); } } })(__concat(v_a, v_chained)); } } })(__concat(v_basic, "|"));

const main = ((s) => { switch(s[0]) { case 0: { const v___w0 = s[1]; return [2, "STRING_TOO_LONG", [0, [0]]]; } case 1: { const v_s = s[1]; return [2, v_s, [0, [0]]]; } } })(v_joined);

function v__lam_7(v_i){
    return String(v_i);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();