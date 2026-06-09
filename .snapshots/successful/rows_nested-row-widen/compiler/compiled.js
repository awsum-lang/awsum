"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
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

  const v_narrow = [995908654, [12, [1]]];

  const v_describe = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1454647603: {
          const v_m = __s[1];
          {
            const __s = v_m;
            switch (__s[0]) {
              case 11: {
                return "N";
              }
              case 12: {
                const v_inner = __s[1];
                {
                  const __s = v_inner;
                  switch (__s[0]) {
                    case 796142685: {
                      const v_b = __s[1];
                      {
                        const __s = v_b;
                        switch (__s[0]) {
                          case 1: {
                            return "T";
                          }
                          case 2: {
                            return "F";
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

  const v_widened = (s => {
    switch (s[0]) {
      case 995908654: {
        const v__lift_14 = s[1];
        return [1454647603, v__lift_13(v__lift_14)];
      }
    }
  })(v_narrow);

  const main = [7, v_describe(v_widened), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
