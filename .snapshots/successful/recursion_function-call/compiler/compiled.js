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

function v_advanceStep(v_x){
  while (true) {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          const __t0 = [1];
          v_x = __t0;
          continue;
        }
        case 1: {
          const __t0 = [2];
          v_x = __t0;
          continue;
        }
        case 2: {
          return "Done!";
        }
      }
    }
  }
}

const main = [2, (v_advanceStep)([0]), [0, [0]]];

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();