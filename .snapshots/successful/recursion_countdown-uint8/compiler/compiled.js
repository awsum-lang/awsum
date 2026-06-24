"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predUInt8 = x => x === 0 ? [3, [17]] : [4, x - 1 & 0xFF];

  const __eqUInt8 = (a, b) => a === b ? [1] : [2];

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

  const v_$apply$countDown = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 20: {
          return v_$x;
        }
        case 21: {
          const v_$pk__21 = v_$k[1];
          switch (v_$x[0]) {
            case 3: {
              v_$k = v_$pk__21;
              continue;
            }
            case 4: {
              const v_s = v_$x[1];
              {
                const __s = __concat(String(v_$k[2]), ",");
                switch (__s[0]) {
                  case 3: {
                    const v_e = __s[1];
                    v_$k = v_$pk__21;
                    v_$x = [3, [589989748, v_e]];
                    continue;
                  }
                  case 4: {
                    const v_s0 = __s[1];
                    v_$k = v_$pk__21;
                    v_$x = (() => {
                      const v_$inl3$____input = __concat(v_s0, v_s);
                      return (s => {
                        switch (s[0]) {
                          case 3: {
                            return [3, [589989748, v_$inl3$____input[1]]];
                          }
                          case 4: {
                            return v_$inl3$____input;
                          }
                        }
                      })(v_$inl3$____input);
                    })();
                    continue;
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$cps$countDown = (v_n, v_$k) => {
    while (true) {
      {
        const __s = __eqUInt8(v_n, 0 & 0xFF);
        switch (__s[0]) {
          case 1: {
            return v_$apply$countDown(v_$k, [4, String(v_n)]);
          }
          case 2: {
            {
              const __s = __predUInt8(v_n);
              switch (__s[0]) {
                case 3: {
                  const v_e = __s[1];
                  return v_$apply$countDown(v_$k, [3, [3768445577, v_e]]);
                }
                case 4: {
                  const v_m = __s[1];
                  v_$k = [21, v_$k, v_n];
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

  const v_$inl8$r = v_$cps$countDown(255 & 0xFF, [20]);
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        {
          const __s = v_$inl8$r[1];
          switch (__s[0]) {
            case 589989748: {
              return [4, "STRING_TOO_LONG"];
            }
            case 3768445577: {
              return __concat("left: ", "UnderflowError");
            }
          }
        }
      }
      case 4: {
        return __concat("right: ", v_$inl8$r[1]);
      }
    }
  })(v_$inl8$r);

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 22: {
          return v_$x;
        }
        case 23: {
          const v_$pk__23 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__23;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$0(
            v_$k,
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [23, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 24: {
          return v_$x;
        }
        case 25: {
          const v_$pk__25 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__25;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [25, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl11$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl11$x[1]];
          }
          case 4: {
            return [5, v_$inl11$x[1]];
          }
        }
      })(v_$inl11$x),
      [24]
    ),
    [22]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
