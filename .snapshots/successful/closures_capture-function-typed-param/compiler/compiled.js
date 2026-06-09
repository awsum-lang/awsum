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

  const v__lam_14 = (v_m) => {
    return v_m;
  };

  const v__apply1 = (v__cl, v__arg0) => {
    {
      const __s = v__cl;
      switch (__s[0]) {
        case 8: {
          return v__lam_14(v__arg0);
        }
      }
    }
  };

  const v__lam_13 = (v_k, v_n) => {
    return v__apply1(v_k, v_n);
  };

  const v__df_applyOnce_0 = (v_x, v__df_applyOnce_0_cap0_0) => {
    return v__lam_13(v__df_applyOnce_0_cap0_0, v_x);
  };

  const v__df_poly_1 = () => {
    return v__df_applyOnce_0(5 | 0, [8]);
  };

  const main = [7, String(v__df_poly_1()), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
