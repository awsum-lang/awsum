"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [16]] : [4, a + b]; }

function v_pureEither(v_x){
    return [4, v_x];
}

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

const v_op1 = [4, (1|0)];

const v_op2 = [3, [435006518, [22]]];

const v_op3 = [4, (3|0)];

const v_f = ((s) => { switch(s[0]) { case 3: { const v__do_e_22_3 = s[1]; return [3, [401451280, v__do_e_22_3]]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_23_3 = s[1]; return [3, v__do_e_23_3]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_24_3 = s[1]; return [3, [451784137, v__do_e_24_3]]; } case 4: { const v_c = s[1]; return (v_pureEither)(v_c); } } })(v_op3); } } })(v_op2); } } })(v_op1);

function v_describe(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 401451280: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 20: {
                      return [4, "ErrorA"];
                    }
                  }
                }
              }
              case 435006518: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 22: {
                      return [4, "ErrorC"];
                    }
                  }
                }
              }
              case 451784137: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 21: {
                      return [4, "ErrorB"];
                    }
                  }
                }
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return __concat("Ok ", String(v_n));
        }
      }
    }
}

const main = (v__let_12)((v_describe)(v_f));

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