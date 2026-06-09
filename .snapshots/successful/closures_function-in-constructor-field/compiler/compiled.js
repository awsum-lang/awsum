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

  const v_triple = v_n => {
    {
      const __s = __addInt32(v_n, v_n);
      switch (__s[0]) {
        case 3: {
          const v__do_e_0 = __s[1];
          return [3, v__do_e_0];
        }
        case 4: {
          const v_m = __s[1];
          return __addInt32(v_m, v_n);
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

  const v_double = v_n => __addInt32(v_n, v_n);

  const v__lift_13 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [589989748, v___f0]];
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
        case 25: {
          return v_double(v__arg0);
        }
        case 26: {
          return v_triple(v__arg0);
        }
      }
    }
  };

  const v_callBox = (v_b, v_x) => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 24: {
          const v_f = __s[1];
          return v__apply1(v_f, v_x);
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
        return (s => {
          switch (s[0]) {
            case 3: {
              const v__do_e_2 = s[1];
              return [3, v__do_e_2];
            }
            case 4: {
              const v_t = s[1];
              return (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_1 = s[1];
                    return [3, [589989748, v__do_e_1]];
                  }
                  case 4: {
                    const v_ds = s[1];
                    return v__lift_13(__concat(v_ds, String(v_t)));
                  }
                }
              })(__concat(String(v_d), " "));
            }
          }
        })(v_callBox([24, [26]], 7 | 0));
      }
    }
  })(v_callBox([24, [25]], 7 | 0));

  const main = (s => {
    switch (s[0]) {
      case 3: {
        const v__e = s[1];
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
