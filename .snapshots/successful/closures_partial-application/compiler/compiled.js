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

function v_wrap(v_s){
    return [0, v_s];
}

function v_unwrap(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v_value = __s[1];
          return v_value;
        }
      }
    }
}

function v_compose(v_f, v_g, v_x){
    return (v_f)((v_g)(v_x));
}

function main(v__input){
    return [2, (v__df_apply_0)("chain", v_unwrap, v_wrap), [0, [0]]];
}

function v__df_apply_0(v_x, v__df_apply_0_cap0_0, v__df_apply_0_cap0_1){
    return (v_compose)(v__df_apply_0_cap0_0, v__df_apply_0_cap0_1, v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();