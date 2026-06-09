"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_whatsThat = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1454647603: {
          const v___rw = __s[1];
          {
            const __s = v___rw;
            switch (__s[0]) {
              case 11: {
                return [4, "Nothing"];
              }
              case 12: {
                const v___pa0 = __s[1];
                {
                  const __s = v___pa0;
                  switch (__s[0]) {
                    case 796142685: {
                      const v_b = __s[1];
                      {
                        const __s = v_b;
                        switch (__s[0]) {
                          case 1: {
                            return [4, "Just True"];
                          }
                          case 2: {
                            return [4, "Just False"];
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

  const v__lift_13 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 11: {
          return [11];
        }
        case 12: {
          const v___f0 = __s[1];
          return [12, [796142685, v___f0]];
        }
      }
    }
  };

  const v__let_14 = v_res => {
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
  };

  const main = v__let_14(v_whatsThat([1454647603, v__lift_13([12, [1]])]));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
