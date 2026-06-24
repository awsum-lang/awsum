"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 29: {
          return v_$x;
        }
        case 30: {
          const v_$pk__30 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__30;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v_$inl7$____pa0 = s[1];
                    switch (v_$inl7$____pa0[0]) {
                      case 2124115655: {
                        {
                          const __s = v_$inl7$____pa0[1];
                          switch (__s[0]) {
                            case 24: {
                              return "y";
                            }
                            case 25: {
                              return "n";
                            }
                          }
                        }
                      }
                      case 2711245919: {
                        return String(v_$inl7$____pa0[1]);
                      }
                    }
                  }
                }
              })([26, [2124115655, [25]]]),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [30, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 27: {
          return v_$x;
        }
        case 28: {
          const v_$pk__28 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__28;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v_$inl10$____pa0 = s[1];
                    switch (v_$inl10$____pa0[0]) {
                      case 2124115655: {
                        {
                          const __s = v_$inl10$____pa0[1];
                          switch (__s[0]) {
                            case 24: {
                              return "y";
                            }
                            case 25: {
                              return "n";
                            }
                          }
                        }
                      }
                      case 2711245919: {
                        return String(v_$inl10$____pa0[1]);
                      }
                    }
                  }
                }
              })([26, [2711245919, 5 | 0]]),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [28, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$andThenIO$0(
    v_$cps$$df$andThenIO$4(
      [
        7,
        (s => {
          switch (s[0]) {
            case 26: {
              const v_$inl13$____pa0 = s[1];
              switch (v_$inl13$____pa0[0]) {
                case 2124115655: {
                  {
                    const __s = v_$inl13$____pa0[1];
                    switch (__s[0]) {
                      case 24: {
                        return "y";
                      }
                      case 25: {
                        return "n";
                      }
                    }
                  }
                }
                case 2711245919: {
                  return String(v_$inl13$____pa0[1]);
                }
              }
            }
          }
        })([26, [2124115655, [24]]]),
        [5, [0]]
      ],
      [29]
    ),
    [27]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
