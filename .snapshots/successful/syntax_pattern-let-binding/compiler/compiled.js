"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [3, [882564211, [14]]]; if (p < -2147483648) return [3, [3768445577, [13]]]; return [4, p|0]; }
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

function v_threeAndDouble(v_n){
    {
      const __s = __mulInt32(v_n, (2|0));
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [11, v_n, v_n];
        }
        case 4: {
          const v_d = __s[1];
          return [11, v_n, v_d];
        }
      }
    }
}

function v_show(v_pair){
    {
      const __s = v_pair;
      switch (__s[0]) {
        case 11: {
          const v_a = __s[1];
          const v_b = __s[2];
          {
            const __s = __concat("[", String(v_a));
            switch (__s[0]) {
              case 3: {
                const v__do_e_13_9 = __s[1];
                return [3, v__do_e_13_9];
              }
              case 4: {
                const v_s0 = __s[1];
                {
                  const __s = __concat(v_s0, ", ");
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_14_9 = __s[1];
                      return [3, v__do_e_14_9];
                    }
                    case 4: {
                      const v_s1 = __s[1];
                      {
                        const __s = __concat(v_s1, String(v_b));
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_15_9 = __s[1];
                            return [3, v__do_e_15_9];
                          }
                          case 4: {
                            const v_s2 = __s[1];
                            return __concat(v_s2, "]");
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
      }
    }
}

const main = (v__let_7)((v_show)((v_threeAndDouble)((5|0))));

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