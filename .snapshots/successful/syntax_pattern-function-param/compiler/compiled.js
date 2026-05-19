"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [3, [882564211, [15]]]; if (s < -2147483648) return [3, [3768445577, [14]]]; return [4, s|0]; }
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

function v_sumTriple(v__arg_6_11){
    {
      const __s = v__arg_6_11;
      switch (__s[0]) {
        case 13: {
          const v_a = __s[1];
          const v_b = __s[2];
          const v_c = __s[3];
          {
            const __s = __addInt32(v_a, v_b);
            switch (__s[0]) {
              case 3: {
                const v___w0 = __s[1];
                return (0|0);
              }
              case 4: {
                const v_ab = __s[1];
                {
                  const __s = __addInt32(v_ab, v_c);
                  switch (__s[0]) {
                    case 3: {
                      const v___w0 = __s[1];
                      return (0|0);
                    }
                    case 4: {
                      const v_abc = __s[1];
                      return v_abc;
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

function v_sumPair(v__arg_16_9){
    {
      const __s = v__arg_16_9;
      switch (__s[0]) {
        case 12: {
          const v_a = __s[1];
          const v_b = __s[2];
          {
            const __s = __addInt32(v_a, v_b);
            switch (__s[0]) {
              case 3: {
                const v___w0 = __s[1];
                return (0|0);
              }
              case 4: {
                const v_s = __s[1];
                return v_s;
              }
            }
          }
        }
      }
    }
}

const v_triple = [13, (10|0), (20|0), (30|0)];

const v_pair = [12, (100|0), (200|0)];

const main = (v__let_15)((v_sumTriple)(v_triple));

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

function v__lam_13(v__arg_29_19){
    {
      const __s = v__arg_29_19;
      switch (__s[0]) {
        case 12: {
          const v_a = __s[1];
          const v_b = __s[2];
          return (v_sumPair)([12, v_a, v_b]);
        }
      }
    }
}

function v__let_14(v_n, v_m){
    return (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_31_9 = s[1]; return [3, v__do_e_31_9]; } case 4: { const v_s0 = s[1]; return __concat(v_s0, String(v_m)); } } })(__concat(String(v_n), " / ")));
}

function v__let_15(v_n){
    return (v__let_14)(v_n, (v__df_apply_0)(v_pair));
}

function v__df_apply_0(v_t){
    return (v__lam_13)(v_t);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();