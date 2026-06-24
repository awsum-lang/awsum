"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v_revInto2 = (v_lst, v_acc) => {
    while (true) {
      switch (v_lst[0]) {
        case 24: {
          return v_acc;
        }
        case 25: {
          const v_s = v_lst[1];
          const v_rest = v_lst[2];
          v_acc = [25, v_s, v_acc];
          v_lst = v_rest;
          continue;
        }
      }
    }
  };

  const v_mk = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_acc;
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  return v_acc;
                }
                case 4: {
                  const v_m = __s[1];
                  v_acc = [25, String(v_n), v_acc];
                  v_n = v_m;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$inl37$xs = v_mk(3 | 0, [24]);
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          return "L";
        }
        case 4: {
          const v_$inl36$z = s[1];
          return v_$inl36$z;
        }
      }
    })(
      __concat(
        (s => {
          switch (s[0]) {
            case 24: {
              return "E";
            }
            case 25: {
              const v_$inl28$r = s[2];
              switch (v_$inl28$r[0]) {
                case 24: {
                  return "e";
                }
                case 25: {
                  return v_$inl28$r[1];
                }
              }
            }
          }
        })(v_revInto2(v_$inl37$xs, [24])),
        (s => {
          switch (s[0]) {
            case 24: {
              return "E";
            }
            case 25: {
              const v_$inl32$r = s[2];
              switch (v_$inl32$r[0]) {
                case 24: {
                  return "e";
                }
                case 25: {
                  return v_$inl32$r[1];
                }
              }
            }
          }
        })(v_$inl37$xs)
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
