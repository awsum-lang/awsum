"use strict";

(() => {
  const __print = (s) => {
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

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const v_step2 = (v_n) => {
    {
      const __s = __mulInt32(v_n, 2 | 0);
      switch (__s[0]) {
        case 3: {
          const v__e = __s[1];
          return [3, "overflow"];
        }
        case 4: {
          const v_m = __s[1];
          return [4, v_m];
        }
      }
    }
  };

  const v_step1 = (v_n) => {
    {
      const __s = __addInt32(v_n, 10 | 0);
      switch (__s[0]) {
        case 3: {
          const v__e = __s[1];
          return [3, "overflow"];
        }
        case 4: {
          const v_m = __s[1];
          return [4, v_m];
        }
      }
    }
  };

  const v_runIO = (v_io) => {
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

  const v_renderErr = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 589989748: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 19: {
                return [4, "STRING_TOO_LONG"];
              }
            }
          }
        }
        case 1615808600: {
          const v_s = __s[1];
          return __concat("err: ", v_s);
        }
      }
    }
  };

  const v__lift_13 = (v___input) => {
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

  const v__let_14 = (v_a, v_prefix) => {
    {
      const __s = v_step2(v_a);
      switch (__s[0]) {
        case 3: {
          const v__do_e_0 = __s[1];
          return [3, [1615808600, v__do_e_0]];
        }
        case 4: {
          const v_b = __s[1];
          return v__lift_13(__concat(v_prefix, String(v_b)));
        }
      }
    }
  };

  const v_run = (v_start) => {
    {
      const __s = v_step1(v_start);
      switch (__s[0]) {
        case 3: {
          const v__do_e_1 = __s[1];
          return [3, [1615808600, v__do_e_1]];
        }
        case 4: {
          const v_a = __s[1];
          return v__let_14(v_a, "answer=");
        }
      }
    }
  };

  const main = ((s) => {
    switch (s[0]) {
      case 3: {
        const v_e = s[1];
        return ((s) => {
          switch (s[0]) {
            case 3: {
              const v___w0 = s[1];
              return [7, "STRING_TOO_LONG", [5, [0]]];
            }
            case 4: {
              const v_out = s[1];
              return [7, v_out, [5, [0]]];
            }
          }
        })(v_renderErr(v_e));
      }
      case 4: {
        const v_s = s[1];
        return [7, v_s, [5, [0]]];
      }
    }
  })(v_run(5 | 0));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
