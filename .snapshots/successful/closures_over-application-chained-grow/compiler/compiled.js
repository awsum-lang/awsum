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

  const v_add3 = (v_a, v__b, v__c) => v_a;

  const v__df_identity_0 = () => [10];

  const v__apply1 = (v__cl, v__arg0) => {
    {
      const __s = v__cl;
      switch (__s[0]) {
        case 8: {
          const v__cap8_0 = __s[1];
          const v__cap8_1 = __s[2];
          return v_add3(v__cap8_0, v__cap8_1, v__arg0);
        }
        case 9: {
          const v__cap9_0 = __s[1];
          return [8, v__cap9_0, v__arg0];
        }
        case 10: {
          return [9, v__arg0];
        }
      }
    }
  };

  const v__let_13 = v_h => [7, String(v__apply1(v_h, 9 | 0)), [5, [0]]];

  const v__let_14 = v_g => v__let_13(v__apply1(v_g, 8 | 0));

  const main = v__let_14(v__apply1(v__df_identity_0(), 7 | 0));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
