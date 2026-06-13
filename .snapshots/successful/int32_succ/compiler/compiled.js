"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

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

  const v_maxInt32 = 2147483647 | 0;

  const main = (v__inl3_r =>
    (() => {
      let v__inl10_scrut;
      $join9: {
        const __s = (s => {
          switch (s[0]) {
            case 3: {
              return __concat("overflow: ", "OverflowError");
            }
            case 4: {
              return __concat("ok: ", String(v__inl3_r[1]));
            }
          }
        })(v__inl3_r);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl10_scrut = (v__inl6_r =>
              (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_1 = s[1];
                    return [3, v__do_e_1];
                  }
                  case 4: {
                    const v_b = s[1];
                    {
                      const __s = __concat(v_a, ", ");
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_0 = __s[1];
                          return [3, v__do_e_0];
                        }
                        case 4: {
                          const v_s0 = __s[1];
                          return __concat(v_s0, v_b);
                        }
                      }
                    }
                  }
                }
              })(
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return __concat("overflow: ", "OverflowError");
                    }
                    case 4: {
                      return __concat("ok: ", String(v__inl6_r[1]));
                    }
                  }
                })(v__inl6_r)
              ))(__succInt32(v_maxInt32));
            break $join9;
          }
        }
      }
      switch (v__inl10_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl10_scrut[1], [5, [0]]];
        }
      }
    })())([4, 43 | 0]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
