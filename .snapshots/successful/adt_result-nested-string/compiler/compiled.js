"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [15]] : [4, a + b]; }

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
        case 19: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 19: {
                const v_value = __s[1];
                return v_value;
              }
              case 20: {
                const v_value = __s[1];
                return v_value;
              }
            }
          }
        }
        case 20: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 19: {
                const v_value = __s[1];
                return v_value;
              }
              case 20: {
                const v_value = __s[1];
                return v_value;
              }
            }
          }
        }
      }
    }
}

const main = (v__let_7)(((s) => { switch(s[0]) { case 3: { const v__do_e_16_9 = s[1]; return [3, v__do_e_16_9]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_17_9 = s[1]; return [3, v__do_e_17_9]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_18_9 = s[1]; return [3, v__do_e_18_9]; } case 4: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_19_9 = s[1]; return [3, v__do_e_19_9]; } case 4: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_20_9 = s[1]; return [3, v__do_e_20_9]; } case 4: { const v_s4 = s[1]; return __concat(v_s4, (v_unwrap)([20, [20, "4"]])); } } })(__concat(v_s3, ",")); } } })(__concat(v_s2, (v_unwrap)([20, [19, "3"]]))); } } })(__concat(v_s1, ",")); } } })(__concat(v_s0, (v_unwrap)([19, [20, "2"]]))); } } })(__concat((v_unwrap)([19, [19, "1"]]), ",")));

function v__let_7(v_res){
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