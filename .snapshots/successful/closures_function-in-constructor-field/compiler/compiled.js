"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
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

  const v_callBox = (v_b, v_x) => {
    {
      const __s = v_b[1];
      switch (__s[0]) {
        case 25: {
          return __addInt32(v_x, v_x);
        }
        case 26: {
          {
            const __s = __addInt32(v_x, v_x);
            switch (__s[0]) {
              case 3: {
                const v__inl3__do_e_0 = __s[1];
                return [3, v__inl3__do_e_0];
              }
              case 4: {
                const v__inl4_m = __s[1];
                return __addInt32(v__inl4_m, v_x);
              }
            }
          }
        }
      }
    }
  };

  const v_formatOutputs = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_3 = s[1];
        return [3, v__do_e_3];
      }
      case 4: {
        const v_d = s[1];
        {
          const __s = v_callBox([24, [26]], 7 | 0);
          switch (__s[0]) {
            case 3: {
              const v__do_e_2 = __s[1];
              return [3, v__do_e_2];
            }
            case 4: {
              const v_t = __s[1];
              {
                const __s = __concat(String(v_d), " ");
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_1 = __s[1];
                    return [3, [589989748, v__do_e_1]];
                  }
                  case 4: {
                    const v_ds = __s[1];
                    const v__inl7___input = __concat(v_ds, String(v_t));
                    switch (v__inl7___input[0]) {
                      case 3: {
                        return [3, [589989748, v__inl7___input[1]]];
                      }
                      case 4: {
                        return v__inl7___input;
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  })(v_callBox([24, [25]], 7 | 0));

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "error", [5, [0]]];
      }
      case 4: {
        const v_s = s[1];
        return [7, v_s, [5, [0]]];
      }
    }
  })(v_formatOutputs);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
