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
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 31: {
          return v__x;
        }
        case 32: {
          const v__pk_32 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_32;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl16_w = [26, [2711245919, 1 | 0], [25]];
          return v__apply__df_andThenIO_8(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v__inl18___p1 = s[2];
                    {
                      const __s = v__inl16_w[1];
                      switch (__s[0]) {
                        case 1615808600: {
                          switch (v__inl18___p1[0]) {
                            case 24: {
                              return "sA";
                            }
                            case 25: {
                              return "sB";
                            }
                          }
                        }
                        case 2711245919: {
                          switch (v__inl18___p1[0]) {
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
              })(v__inl16_w),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [32, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 29: {
          return v__x;
        }
        case 30: {
          const v__pk_30 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_30;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl21_w = [26, [1615808600, "x"], [24]];
          return v__apply__df_andThenIO_4(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v__inl23___p1 = s[2];
                    {
                      const __s = v__inl21_w[1];
                      switch (__s[0]) {
                        case 1615808600: {
                          switch (v__inl23___p1[0]) {
                            case 24: {
                              return "sA";
                            }
                            case 25: {
                              return "sB";
                            }
                          }
                        }
                        case 2711245919: {
                          switch (v__inl23___p1[0]) {
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
              })(v__inl21_w),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [30, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_28;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl26_w = [26, [1615808600, "x"], [25]];
          return v__apply__df_andThenIO_0(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 26: {
                    const v__inl28___p1 = s[2];
                    {
                      const __s = v__inl26_w[1];
                      switch (__s[0]) {
                        case 1615808600: {
                          switch (v__inl28___p1[0]) {
                            case 24: {
                              return "sA";
                            }
                            case 25: {
                              return "sB";
                            }
                          }
                        }
                        case 2711245919: {
                          switch (v__inl28___p1[0]) {
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
              })(v__inl26_w),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [28, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl35_w = [26, [2711245919, 1 | 0], [24]];
  const main = v__cps__df_andThenIO_0(
    v__cps__df_andThenIO_4(
      v__cps__df_andThenIO_8(
        [
          7,
          (s => {
            switch (s[0]) {
              case 26: {
                const v__inl32___p1 = s[2];
                {
                  const __s = v__inl35_w[1];
                  switch (__s[0]) {
                    case 1615808600: {
                      switch (v__inl32___p1[0]) {
                        case 24: {
                          return "sA";
                        }
                        case 25: {
                          return "sB";
                        }
                      }
                    }
                    case 2711245919: {
                      switch (v__inl32___p1[0]) {
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
          })(v__inl35_w),
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
