"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __mulInt32 = (a, b) => {
    const r = a * b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const main = (v__inl10_pair =>
    (() => {
      let v__inl14_scrut;
      $join13: {
        const __s = __concat("[", String(v__inl10_pair[1]));
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v__inl5_s0 = __s[1];
            v__inl14_scrut = (s => {
              switch (s[0]) {
                case 3: {
                  const v__inl6__do_e_1 = s[1];
                  return [3, v__inl6__do_e_1];
                }
                case 4: {
                  const v__inl7_s1 = s[1];
                  {
                    const __s = __concat(v__inl7_s1, String(v__inl10_pair[2]));
                    switch (__s[0]) {
                      case 3: {
                        const v__inl8__do_e_0 = __s[1];
                        return [3, v__inl8__do_e_0];
                      }
                      case 4: {
                        const v__inl9_s2 = __s[1];
                        return __concat(v__inl9_s2, "]");
                      }
                    }
                  }
                }
              }
            })(__concat(v__inl5_s0, ", "));
            break $join13;
          }
        }
      }
      switch (v__inl14_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl14_scrut[1], [5, [0]]];
        }
      }
    })())(
    (v__inl3_n =>
      (s => {
        switch (s[0]) {
          case 3: {
            return [15, v__inl3_n, v__inl3_n];
          }
          case 4: {
            const v__inl2_d = s[1];
            return [15, v__inl3_n, v__inl2_d];
          }
        }
      })(__mulInt32(v__inl3_n, 2 | 0)))(5 | 0)
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
