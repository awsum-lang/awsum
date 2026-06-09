"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_showResult = v_r => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 2252990199: {
                const v__a = __s[1];
                return "ERR_A";
              }
              case 2269767818: {
                const v__b = __s[1];
                return "ERR_B";
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

  const v_oa = [4, 10 | 0];

  const v_cont = v_n => [4, v_n];

  const v__lift_13 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2269767818, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__df_identity_0 = v__df_identity_0_cap0_0 =>
    [8, v__df_identity_0_cap0_0];

  const v__apply__scc__apply1__rowmono_0_bindEither = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 12: {
            return v__x;
          }
          case 13: {
            const v__pk_13 = __s[1];
            const __t0 = v__pk_13;
            const __t1 = v__lift_13(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__rowmono_0_bindEither = (v__args, v__k) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 10: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 8: {
                  const v__cap8_0 = __s[1];
                  const __t0 = (v__args[0] = 11, v__args[1] = v__cap8_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 9: {
                  return v__apply__scc__apply1__rowmono_0_bindEither(
                    v__k,
                    v_cont(v__arg0)
                  );
                }
              }
            }
          }
          case 11: {
            const v_x = __s[1];
            const v_k = __s[2];
            {
              const __s = v_x;
              switch (__s[0]) {
                case 3: {
                  const v_e = __s[1];
                  return v__apply__scc__apply1__rowmono_0_bindEither(
                    v__k,
                    [3, [2252990199, v_e]]
                  );
                }
                case 4: {
                  const v_a = __s[1];
                  const __t0 = (v__args[0] = 10, v__args[1] = v_k, v__args[2] = v_a, v__args);
                  const __t1 = [13, v__k];
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__scc__apply1__rowmono_0_bindEither = v__args =>
    v__cps__scc__apply1__rowmono_0_bindEither(v__args, [12]);

  const v__apply1 = (v__cl, v__arg0) =>
    v__scc__apply1__rowmono_0_bindEither([10, v__cl, v__arg0]);

  const v_result = v__apply1(v__df_identity_0(v_oa), [9]);

  const main = [7, v_showResult(v_result), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
