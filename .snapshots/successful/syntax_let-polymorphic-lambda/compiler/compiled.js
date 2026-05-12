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

function v_showTri(v_t){
    {
      const __s = v_t;
      switch (__s[0]) {
        case 19: {
          return "A";
        }
      }
    }
}

function v_threeTypes(v_n, v_s, v_b){
    return (v__df__let_8_0)(v_b, v_n, v_s);
}

const main = (v__let_9)((v_threeTypes)((42|0), "hello", [19]));

function v__lam_7(v_x){
    return v_x;
}

function v__let_9(v_res){
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

function v__df__let_8_0(v_b, v_n, v_s){
    {
      const __s = __concat(String((v__lam_7)(v_n)), "/");
      switch (__s[0]) {
        case 3: {
          const v__do_e_20_9 = __s[1];
          return [3, v__do_e_20_9];
        }
        case 4: {
          const v_s0 = __s[1];
          {
            const __s = __concat(v_s0, (v__lam_7)(v_s));
            switch (__s[0]) {
              case 3: {
                const v__do_e_21_9 = __s[1];
                return [3, v__do_e_21_9];
              }
              case 4: {
                const v_s1 = __s[1];
                {
                  const __s = __concat(v_s1, "/");
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_22_9 = __s[1];
                      return [3, v__do_e_22_9];
                    }
                    case 4: {
                      const v_s2 = __s[1];
                      return __concat(v_s2, (v_showTri)((v__lam_7)(v_b)));
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();