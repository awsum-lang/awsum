"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_summary = (v__inl2___input =>
    (s => {
      switch (s[0]) {
        case 3: {
          const v__do_e_5 = s[1];
          return [3, v__do_e_5];
        }
        case 4: {
          const v_a = s[1];
          const v__inl7___input = [12, [0]];
          {
            const __s = (s => {
              switch (s[0]) {
                case 11: {
                  return [4, "Nothing"];
                }
                case 12: {
                  const v__inl8___pa0 = s[1];
                  switch (v__inl8___pa0[0]) {
                    case 796142685: {
                      {
                        const __s = v__inl8___pa0[1];
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
                    case 1759602215: {
                      return __concat("Just ", "Unit");
                    }
                  }
                }
              }
            })(
              (s => {
                switch (s[0]) {
                  case 11: {
                    return v__inl7___input;
                  }
                  case 12: {
                    return [12, [1759602215, v__inl7___input[1]]];
                  }
                }
              })(v__inl7___input)
            );
            switch (__s[0]) {
              case 3: {
                const v__do_e_4 = __s[1];
                return [3, v__do_e_4];
              }
              case 4: {
                const v_b = __s[1];
                {
                  const __s = __concat(v_a, "; ");
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_2 = __s[1];
                      return [3, v__do_e_2];
                    }
                    case 4: {
                      const v_s0 = __s[1];
                      {
                        const __s = __concat(v_s0, v_b);
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_1 = __s[1];
                            return [3, v__do_e_1];
                          }
                          case 4: {
                            const v_s1 = __s[1];
                            {
                              const __s = __concat(v_s1, "; ");
                              switch (__s[0]) {
                                case 3: {
                                  const v__do_e_0 = __s[1];
                                  return [3, v__do_e_0];
                                }
                                case 4: {
                                  const v_s2 = __s[1];
                                  return __concat(v_s2, "Nothing");
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
        }
      }
    })(
      (s => {
        switch (s[0]) {
          case 11: {
            return [4, "Nothing"];
          }
          case 12: {
            const v__inl3___pa0 = s[1];
            switch (v__inl3___pa0[0]) {
              case 796142685: {
                {
                  const __s = v__inl3___pa0[1];
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
              case 1759602215: {
                return __concat("Just ", "Unit");
              }
            }
          }
        }
      })(
        (s => {
          switch (s[0]) {
            case 11: {
              return v__inl2___input;
            }
            case 12: {
              return [12, [796142685, v__inl2___input[1]]];
            }
          }
        })(v__inl2___input)
      )
    ))([12, [1]]);

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

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        const v__inl15_s = s[1];
        return [7, v__inl15_s, [5, [0]]];
      }
    }
  })(v_summary);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
