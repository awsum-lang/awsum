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

  const v_ob = [4, 5 | 0];

  const v_oa = [3, [24]];

  const v_de = v_x => {
    {
      const __s = v_x;
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

  const v_const = (v_x, v__y) => v_x;

  const v__lift_15 = v___input => {
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

  const v__lam_13 = v__n => v_ob;

  const v__df__rowmono_1_andThenEither_1 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [332136403, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_15(v__lam_13(v_a));
        }
      }
    }
  };

  const v_c2 = v__df__rowmono_1_andThenEither_1(v_oa);

  const v__lam_14 = v__u => [7, v_de(v_c2), [5, [0]]];

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
          return v__lift_15(v_const(v__df__rowmono_0_bindEither_0_cap1_0, v_a));
        }
      }
    }
  };

  const v_c1 = v__df__rowmono_0_bindEither_0(v_oa, v_ob);

  const v__apply__df_andThenIO_2 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 25: {
            return v__x;
          }
          case 26: {
            const v__pk_26 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_26;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_2 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_2(v__k, v__lam_14(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 26, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_2 = v_io => v__cps__df_andThenIO_2(v_io, [25]);

  const main = v__df_andThenIO_2([7, v_de(v_c1), [5, [0]]]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
