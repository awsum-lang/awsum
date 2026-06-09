"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_zeroOr = (v__n) => {
    return [3, [751576878, [26]]];
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

  const v_describe = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 751576878: {
                const v__z = __s[1];
                return "Z";
              }
            }
          }
        }
        case 4: {
          const v_v = __s[1];
          return String(v_v);
        }
      }
    }
  };

  const v_called = v_zeroOr(9 | 0);

  const main = [7, v_describe(v_called), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
