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

  const v_pureEither = v_x => [4, v_x];

  const v_ob = [3, [25]];

  const v_oaInner = [4, 1 | 0];

  const v_oa = [4, 2 | 0];

  const v_describe = v_r => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 332136403: {
                const v__a = __s[1];
                return "A";
              }
              case 348914022: {
                const v__b = __s[1];
                return "B";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v__lam_13 = v__n => {
    {
      const __s = v_oaInner;
      switch (__s[0]) {
        case 3: {
          const v__do_e_1 = __s[1];
          return [3, [332136403, v__do_e_1]];
        }
        case 4: {
          const v_x = __s[1];
          {
            const __s = v_ob;
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                return [3, [348914022, v__do_e_0]];
              }
              case 4: {
                const v_y = __s[1];
                return v_pureEither(v_y);
              }
            }
          }
        }
      }
    }
  };

  const v__df__rowmono_0_bindEither_0 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [332136403, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lam_13(v_a);
        }
      }
    }
  };

  const v_cShared = v__df__rowmono_0_bindEither_0(v_oa);

  const main = [7, v_describe(v_cShared), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
