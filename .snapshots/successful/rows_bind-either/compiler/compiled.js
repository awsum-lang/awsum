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

function v_opA(v_n){
    return [4, v_n];
}

function v_opB(v__n){
    return [3, [20]];
}

function v_run(v_x){
    {
      const __s = (v_opA)(v_x);
      switch (__s[0]) {
        case 3: {
          const v__do_e_19_3 = __s[1];
          return [3, [2252990199, v__do_e_19_3]];
        }
        case 4: {
          const v_a = __s[1];
          return (v__lift_7)((v_opB)(v_a));
        }
      }
    }
}

function v_describe(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 2252990199: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 19: {
                      return [4, "ErrA"];
                    }
                  }
                }
              }
              case 2269767818: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 20: {
                      return [4, "ErrB"];
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

const main = (v__let_8)((v_describe)((v_run)((5|0))));

function v__lift_7(v___input){
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2269767818, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
}

function v__let_8(v_res){
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