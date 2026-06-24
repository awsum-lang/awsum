"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_loop = (v_fuel, v_xs, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_fuel, 0 | 0);
        switch (__s[0]) {
          case 1: {
            switch (v_acc[0]) {
              case 24: {
                return "N";
              }
              case 25: {
                return String(v_acc[1]);
              }
            }
          }
          case 2: {
            switch (v_xs[0]) {
              case 24: {
                switch (v_acc[0]) {
                  case 24: {
                    return "N";
                  }
                  case 25: {
                    return String(v_acc[1]);
                  }
                }
              }
              case 25: {
                const v_t = v_xs[2];
                {
                  const __s = __predInt32(v_fuel);
                  switch (__s[0]) {
                    case 3: {
                      switch (v_acc[0]) {
                        case 24: {
                          return "N";
                        }
                        case 25: {
                          return String(v_acc[1]);
                        }
                      }
                    }
                    case 4: {
                      const v_f2 = __s[1];
                      v_fuel = v_f2;
                      v_acc = v_xs;
                      v_xs = [25, 7 | 0, v_t];
                      continue;
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

  const main = [
    7,
    v_loop(1 | 0, [25, 1 | 0, [25, 2 | 0, [24]]], [24]),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
