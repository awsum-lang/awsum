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

const v_firstZero = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 11: {
          return (0|0);
        }
        case 12: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 11: {
                return (0|0);
              }
              case 12: {
                const v_n = __s[1];
                return v_n;
              }
            }
          }
        }
      }
    }
};

const v__lift_23 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 11: {
          return [11];
        }
        case 12: {
          const v___f0 = __s[1];
          return [12, v___f0];
        }
      }
    }
};

const main = [7, String((v_firstZero)((v__lift_23)([11]))), [5, [0]]];

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();