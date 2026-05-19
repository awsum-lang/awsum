"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [16]] : [4, a + b]; }

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

function v_unwrap(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return __concat("left: ", v_e);
        }
        case 4: {
          const v_v = __s[1];
          return __concat("right: ", v_v);
        }
      }
    }
}

const main = (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_13_9 = s[1]; return [3, v__do_e_13_9]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_14_9 = s[1]; return [3, v__do_e_14_9]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_15_9 = s[1]; return [3, v__do_e_15_9]; } case 4: { const v_s0 = s[1]; return __concat(v_s0, v_b); } } })(__concat(v_a, ", ")); } } })((v_unwrap)([4, "good"])); } } })((v_unwrap)([3, "bad"])));

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