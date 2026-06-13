"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

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

  const v_zero = 0 | 0;

  const v_sumList = (v_lst, v_acc) => {
    while (true) {
      switch (v_lst[0]) {
        case 13: {
          return v_acc;
        }
        case 14: {
          {
            const __s = __addInt32(v_acc, v_lst[1]);
            switch (__s[0]) {
              case 3: {
                return v_acc;
              }
              case 4: {
                const v_next = __s[1];
                v_lst = v_lst[2];
                v_acc = v_next;
                continue;
              }
            }
          }
        }
      }
    }
  };

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

  const v_revInto = (v_acc, v_lst) => {
    while (true) {
      switch (v_lst[0]) {
        case 13: {
          return v_acc;
        }
        case 14: {
          const v_h = v_lst[1];
          const v_t = v_lst[2];
          v_acc = [14, v_h, v_acc];
          v_lst = v_t;
          continue;
        }
      }
    }
  };

  const v_revN = (v_times, v_lst) => {
    while (true) {
      {
        const __s = __eqInt32(v_times, v_zero);
        switch (__s[0]) {
          case 1: {
            return v_lst;
          }
          case 2: {
            {
              const __s = __predInt32(v_times);
              switch (__s[0]) {
                case 3: {
                  return v_lst;
                }
                case 4: {
                  const v_m = __s[1];
                  v_times = v_m;
                  v_lst = v_revInto([13], v_lst);
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__apply_repeat = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 15: {
          return v__x;
        }
        case 16: {
          const v__pk_16 = v__k[1];
          v__x = (v__k[0] = 14, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_16;
          continue;
        }
      }
    }
  };

  const v__cps_repeat = (v_n, v_value, v__k) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, v_zero);
        switch (__s[0]) {
          case 1: {
            return v__apply_repeat(v__k, [13]);
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  return v__apply_repeat(v__k, [13]);
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  v__k = [16, v__k, v_value];
                  continue;
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
    String(
      v_sumList(
        v_revN(1000 | 0, v__cps_repeat(100000 | 0, 1 | 0, [15])),
        v_zero
      )
    ),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
