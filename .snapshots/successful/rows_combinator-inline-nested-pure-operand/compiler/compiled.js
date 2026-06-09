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

  const v_pureEither = (v_x) => {
    return [4, v_x];
  };

  const v_ob = [4, 5 | 0];

  const v_describe = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 348914022: {
                const v__b = __s[1];
                return "B";
              }
              case 365691641: {
                const v__c = __s[1];
                return "C";
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

  const v__lam_13 = (v__m) => {
    return [3, [365691641, [26]]];
  };

  const v__df__rowmono_1_bindEither_1 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [348914022, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lam_13(v_a);
        }
      }
    }
  };

  const v__lam_14 = (v__n) => {
    return v__df__rowmono_1_bindEither_1(v_ob);
  };

  const v__df__rowmono_0_bindEither_0 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v__lam_14(v_a);
        }
      }
    }
  };

  const v_cPure = (v_n) => {
    return v__df__rowmono_0_bindEither_0(v_pureEither(v_n));
  };

  const main = [7, v_describe(v_cPure(7 | 0)), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
