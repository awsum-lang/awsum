"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

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

const main = [7, (v__df_apply_0)((42|0)), [5, [0]]];

function v__bi_showInt32(v__x0){
    return String(v__x0);
}

function v__df_apply_0(v_x){
    return (v__bi_showInt32)(v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();