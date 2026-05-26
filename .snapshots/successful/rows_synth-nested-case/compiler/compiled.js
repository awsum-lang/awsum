"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

const v_runIO = (v_io) => {
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
};

const v_dispatch = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1615808600: {
          const v__s = __s[1];
          return "s";
        }
      }
    }
};

const main = ((s) => { switch(s[0]) { case 10: { return [7, "n", [5, [0]]]; } case 11: { const v_x = s[1]; return [7, (v_dispatch)([1615808600, v_x]), [5, [0]]]; } } })(((s) => { switch(s[0]) { case 1: { return [11, "yes"]; } case 2: { return [10]; } } })([1]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();