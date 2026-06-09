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

  const v_oa = [4, 1 | 0];

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
          const v_v = __s[1];
          return String(v_v);
        }
      }
    }
  };

  const v_cont = v__n => [3, [25]];

  const v__lift_14 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [348914022, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__apply1 = (v__cl, v__arg0) => {
    {
      const __s = v__cl;
      switch (__s[0]) {
        case 26: {
          return v_cont(v__arg0);
        }
      }
    }
  };

  const v__lam_13 = (v_k, v_n) => v__apply1(v_k, v_n);

  const v__df__rowmono_0_bindEither_0 = (
    v_x,
    v__df__rowmono_0_bindEither_0_cap1_0
  ) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [332136403, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_14(
            v__lam_13(v__df__rowmono_0_bindEither_0_cap1_0, v_a)
          );
        }
      }
    }
  };

  const v__df_poly_1 = () => v__df__rowmono_0_bindEither_0(v_oa, [26]);

  const main = [7, v_describe(v__df_poly_1()), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
