"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

function v_pureEither(v_x){
    return [1, v_x];
}

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

const v_op1 = [1, (1|0)];

const v_op2 = [0, [435006518, [0]]];

const v_op3 = [1, (3|0)];

const v_f = ((s) => { switch(s[0]) { case 0: { const v__do_e_22_3 = s[1]; return [0, [401451280, v__do_e_22_3]]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_3 = s[1]; return [0, v__do_e_23_3]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_3 = s[1]; return [0, [451784137, v__do_e_24_3]]; } case 1: { const v_c = s[1]; return (v_pureEither)(v_c); } } })(v_op3); } } })(v_op2); } } })(v_op1);

function v_describe(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 401451280: {
                const v___rw = __s[1];
                return [1, "ErrorA"];
              }
              case 435006518: {
                const v___rw = __s[1];
                return [1, "ErrorC"];
              }
              case 451784137: {
                const v___rw = __s[1];
                return [1, "ErrorB"];
              }
            }
          }
        }
        case 1: {
          const v_n = __s[1];
          return [1, ("Ok " + String(v_n))];
        }
      }
    }
}

function main(v__input){
    return (v__let_2)((v_describe)(v_f));
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