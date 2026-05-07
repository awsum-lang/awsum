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

const v_zero = (0|0);

function v_both(v_a, v_b){
    return (v__df_apply_0)(v_zero, v_a, v_b);
}

function v_bothBody(v_a, v_b){
    {
      const __s = __concat(String(v_a), "/");
      switch (__s[0]) {
        case 0: {
          const v__do_e_15_3 = __s[1];
          return [0, v__do_e_15_3];
        }
        case 1: {
          const v_s0 = __s[1];
          return __concat(v_s0, String(v_b));
        }
      }
    }
}

function main(v__input){
    return (v__let_3)((v_both)((11|0), (22|0)));
}

function v__lam_2(v_a, v_b, v__n){
    return (v_bothBody)(v_a, v_b);
}

function v__let_3(v_res){
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

function v__df_apply_0(v_x, v__df_apply_0_cap0_0, v__df_apply_0_cap0_1){
    return (v__lam_2)(v__df_apply_0_cap0_0, v__df_apply_0_cap0_1, v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();