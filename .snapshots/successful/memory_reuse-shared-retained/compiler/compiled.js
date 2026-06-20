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
          const v__inl0_eff = __print(v_io[1]);
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

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 26: {
          return v__x;
        }
        case 27: {
          const v__pk_27 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_27;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__df_andThenIO_0_cap0_0, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_0(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 24: {
                    return "E";
                  }
                  case 25: {
                    const v__inl6_r = s[2];
                    switch (v__inl6_r[0]) {
                      case 24: {
                        return "e";
                      }
                      case 25: {
                        return v__inl6_r[1];
                      }
                    }
                  }
                }
              })(v__df_andThenIO_0_cap0_0),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [27, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl17_xs = v_mk(3 | 0, [24]);
  const main = v__cps__df_andThenIO_0(
    [
      7,
      (s => {
        switch (s[0]) {
          case 24: {
            return "E";
          }
          case 25: {
            const v__inl14_r = s[2];
            switch (v__inl14_r[0]) {
              case 24: {
                return "e";
              }
              case 25: {
                return v__inl14_r[1];
              }
            }
          }
        }
      })(v_revInto2(v__inl17_xs, [24])),
      [5, [0]]
    ],
    v__inl17_xs,
    [26]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
