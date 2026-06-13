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

  const main = (v__inl2_m =>
    (() => {
      let v__inl8_scrut;
      $join7: {
        const __s = (s => {
          switch (s[0]) {
            case 11: {
              return [4, "nothing"];
            }
            case 12: {
              return __concat("just: ", v__inl2_m[1]);
            }
          }
        })(v__inl2_m);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl8_scrut = (v__inl4_m =>
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
                    case 11: {
                      return [4, "nothing"];
                    }
                    case 12: {
                      return __concat("just: ", v__inl4_m[1]);
                    }
                  }
                })(v__inl4_m)
              ))([11]);
            break $join7;
          }
        }
      }
      switch (v__inl8_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl8_scrut[1], [5, [0]]];
        }
      }
    })())([12, "hi"]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
