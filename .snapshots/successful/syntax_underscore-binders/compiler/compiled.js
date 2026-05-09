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

function v_greeting(v__wild0){
    return "hi";
}

function v_unwrapBox(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 19: {
          const v___w0 = __s[1];
          return "unwrapped";
        }
      }
    }
}

function v_unwrapBoxNamed(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 19: {
          const v__v = __s[1];
          return "unwrapped-named";
        }
      }
    }
}

function v_showPair(v_p){
    {
      const __s = v_p;
      switch (__s[0]) {
        case 20: {
          const v___w0 = __s[1];
          const v___w1 = __s[2];
          return "paired";
        }
      }
    }
}

const main = (v__let_7)(((s) => { switch(s[0]) { case 3: { const v__do_e_26_9 = s[1]; return [3, v__do_e_26_9]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_27_9 = s[1]; return [3, v__do_e_27_9]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_28_9 = s[1]; return [3, v__do_e_28_9]; } case 4: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_29_9 = s[1]; return [3, v__do_e_29_9]; } case 4: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_30_9 = s[1]; return [3, v__do_e_30_9]; } case 4: { const v_s4 = s[1]; return __concat(v_s4, (v_showPair)([20, "l", "r"])); } } })(__concat(v_s3, " ")); } } })(__concat(v_s2, (v_unwrapBoxNamed)([19, "b"]))); } } })(__concat(v_s1, " ")); } } })(__concat(v_s0, (v_unwrapBox)([19, "a"]))); } } })(__concat((v_greeting)("x"), " ")));

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