"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

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

const v_answer = (42|0);

function v_captureFn(v_k){
    return (v__df_apply_0)(v_answer, v_k);
}

function main(v__input){
    return [2, String((v_captureFn)((7|0))), [0, [0]]];
}

function v__lam_2(v_k, v__n){
    return v_k;
}

function v__df_apply_0(v_x, v__df_apply_0_cap0_0){
    return (v__lam_2)(v__df_apply_0_cap0_0, v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();