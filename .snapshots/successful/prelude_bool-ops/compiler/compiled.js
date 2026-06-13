"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
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

  const main = (() => {
    let v__inl10_scrut;
    $join9: {
      const __s = __concat("False", "True");
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s0 = __s[1];
          v__inl10_scrut = (s => {
            switch (s[0]) {
              case 3: {
                const v__do_e_2 = s[1];
                return [3, v__do_e_2];
              }
              case 4: {
                const v_s1 = s[1];
                {
                  const __s = __concat(v_s1, "True");
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_1 = __s[1];
                      return [3, v__do_e_1];
                    }
                    case 4: {
                      const v_s2 = __s[1];
                      {
                        const __s = __concat(v_s2, "False");
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_0 = __s[1];
                            return [3, v__do_e_0];
                          }
                          case 4: {
                            const v_s3 = __s[1];
                            return __concat(v_s3, "True");
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          })(
            __concat(
              v_s0,
              (v__inl1_a =>
                (() => {
                  let v__inl8_scrut;
                  $join7: {
                    switch (v__inl1_a[0]) {
                      case 1: {
                        return "False";
                      }
                      case 2: {
                        v__inl8_scrut = v__inl1_a;
                        break $join7;
                      }
                    }
                  }
                  switch (v__inl8_scrut[0]) {
                    case 1: {
                      return "True";
                    }
                    case 2: {
                      return "False";
                    }
                  }
                })())([1])
            )
          );
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
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
