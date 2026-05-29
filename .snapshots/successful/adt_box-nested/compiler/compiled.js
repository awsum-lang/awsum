"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

const v_unwrap = (v_b) => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 22: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 22: {
                const v___p0_p0 = __s[1];
                {
                  const __s = v___p0_p0;
                  switch (__s[0]) {
                    case 22: {
                      const v_value = __s[1];
                      return v_value;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
};

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

const main = [7, (v_unwrap)([22, [22, [22, "hello"]]]), [5, [0]]];

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();