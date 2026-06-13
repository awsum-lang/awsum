"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_oa = [4, 10 | 0];

  const v__apply__scc__apply1__rowmono_0_bindEither = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 12: {
          return v__x;
        }
        case 13: {
          const __t0 = v__k[1];
          const __t1 = (s => {
            switch (s[0]) {
              case 3: {
                const v__inl1___f0 = s[1];
                return (v__k[0] = 3, v__k[1] = [
                  2269767818,
                  v__inl1___f0
                ], v__k);
              }
              case 4: {
                return v__x;
              }
            }
          })(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  };

  const v__cps__scc__apply1__rowmono_0_bindEither = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 10: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 8: {
              v__args = (v__args[0] = 11, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 9: {
              return v__apply__scc__apply1__rowmono_0_bindEither(
                v__k,
                [4, v__arg0]
              );
            }
          }
        }
        case 11: {
          const v_x = v__args[1];
          switch (v_x[0]) {
            case 3: {
              const v_e = v_x[1];
              return v__apply__scc__apply1__rowmono_0_bindEither(
                v__k,
                [3, [2252990199, v_e]]
              );
            }
            case 4: {
              const v_a = v_x[1];
              v__args = (v__args[0] = 10, v__args[1] = v__args[2], v__args[2] = v_a, v__args);
              v__k = [13, v__k];
              continue;
            }
          }
        }
      }
    }
  };

  const v_result = v__cps__scc__apply1__rowmono_0_bindEither(
    [10, [8, v_oa], [9]],
    [12]
  );

  const main = [
    7,
    (v__inl7_r =>
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v__inl7_r[1];
              switch (__s[0]) {
                case 2252990199: {
                  return "ERR_A";
                }
                case 2269767818: {
                  return "ERR_B";
                }
              }
            }
          }
          case 4: {
            return String(v__inl7_r[1]);
          }
        }
      })(v__inl7_r))(v_result),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
