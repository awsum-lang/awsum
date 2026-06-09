"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_runIO = v_io => {
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

  const v_inc = v_n => v_n;

  const v__scc__apply1_applyOnce = v__args => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 11: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 8: {
                  const v__cap8_0 = __s[1];
                  const __t0 = (v__args[0] = 12, v__args[1] = v__cap8_0, v__args[2] = v__arg0, v__args);
                  v__args = __t0;
                  continue;
                }
                case 9: {
                  return v_inc(v__arg0);
                }
                case 10: {
                  return [8, v__arg0];
                }
              }
            }
          }
          case 12: {
            const v_f = __s[1];
            const v_x = __s[2];
            const __t0 = (v__args[0] = 11, v__args[1] = v_f, v__args[2] = v_x, v__args);
            v__args = __t0;
            continue;
          }
        }
      }
    }
  };

  const v_applyOnce = (v_f, v_x) => v__scc__apply1_applyOnce([12, v_f, v_x]);

  const v__df_identity_0 = () => [10];

  const v__apply2 = (v__cl, v__arg0, v__arg1) => {
    {
      const __s = v__cl;
      switch (__s[0]) {
        case 10: {
          return v_applyOnce(v__arg0, v__arg1);
        }
      }
    }
  };

  const main = [7, String(v__apply2(v__df_identity_0(), [9], 5 | 0)), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
