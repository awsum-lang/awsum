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

  const v_$apply$$df$andThenIO$8 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 31: {
          return v_$x;
        }
        case 32: {
          const v_$pk__32 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__32;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl16$w = [26, [2711245919, 1 | 0], [25]];
          return v_$apply$$df$andThenIO$8(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v_$inl18$____p1 = s[2];
                    {
                      const __s = v_$inl16$w[1];
                      switch (__s[0]) {
                        case 1615808600: {
                          switch (v_$inl18$____p1[0]) {
                            case 24: {
                              return "sA";
                            }
                            case 25: {
                              return "sB";
                            }
                          }
                        }
                        case 2711245919: {
                          switch (v_$inl18$____p1[0]) {
                            case 24: {
                              return "iA";
                            }
                            case 25: {
                              return "iB";
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })(v_$inl16$w),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [32, v_$k, v_s];
          v_io = v_next;
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
          const v_$inl21$w = [26, [1615808600, "x"], [24]];
          return v_$apply$$df$andThenIO$4(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v_$inl23$____p1 = s[2];
                    {
                      const __s = v_$inl21$w[1];
                      switch (__s[0]) {
                        case 1615808600: {
                          switch (v_$inl23$____p1[0]) {
                            case 24: {
                              return "sA";
                            }
                            case 25: {
                              return "sB";
                            }
                          }
                        }
                        case 2711245919: {
                          switch (v_$inl23$____p1[0]) {
                            case 24: {
                              return "iA";
                            }
                            case 25: {
                              return "iB";
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })(v_$inl21$w),
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
          const v_$inl26$w = [26, [1615808600, "x"], [25]];
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v_$inl28$____p1 = s[2];
                    {
                      const __s = v_$inl26$w[1];
                      switch (__s[0]) {
                        case 1615808600: {
                          switch (v_$inl28$____p1[0]) {
                            case 24: {
                              return "sA";
                            }
                            case 25: {
                              return "sB";
                            }
                          }
                        }
                        case 2711245919: {
                          switch (v_$inl28$____p1[0]) {
                            case 24: {
                              return "iA";
                            }
                            case 25: {
                              return "iB";
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })(v_$inl26$w),
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

  const v_$inl35$w = [26, [2711245919, 1 | 0], [24]];
  const main = v_$cps$$df$andThenIO$0(
    v_$cps$$df$andThenIO$4(
      v_$cps$$df$andThenIO$8(
        [
          7,
          (s => {
            switch (s[0]) {
              case 26: {
                const v_$inl32$____p1 = s[2];
                {
                  const __s = v_$inl35$w[1];
                  switch (__s[0]) {
                    case 1615808600: {
                      switch (v_$inl32$____p1[0]) {
                        case 24: {
                          return "sA";
                        }
                        case 25: {
                          return "sB";
                        }
                      }
                    }
                    case 2711245919: {
                      switch (v_$inl32$____p1[0]) {
                        case 24: {
                          return "iA";
                        }
                        case 25: {
                          return "iB";
                        }
                      }
                    }
                  }
                }
              }
            }
          })(v_$inl35$w),
          [5, [0]]
        ],
        [31]
      ),
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
