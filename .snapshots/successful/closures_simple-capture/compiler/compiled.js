"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
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

  const v_answer = 42 | 0;

  const v__lam_18 = (v_k, v__n) => {
    return v_k;
  };

  const v__df_apply_0 = (v_x, v__df_apply_0_cap0_0) => {
    return v__lam_18(v__df_apply_0_cap0_0, v_x);
  };

  const v_captureFn = (v_k) => {
    return v__df_apply_0(v_answer, v_k);
  };

  const main = [7, String(v_captureFn(7 | 0)), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
