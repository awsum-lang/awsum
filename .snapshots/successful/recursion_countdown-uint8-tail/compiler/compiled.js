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
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_countDown = (v_n, v_acc) => {
    while (true) {
      {
        const __s = __eqUInt8(v_n, 0 & 0xFF);
        switch (__s[0]) {
          case 1: {
            const v__inl3___input = __concat(v_acc, String(v_n));
            switch (v__inl3___input[0]) {
              case 3: {
                return [3, [589989748, v__inl3___input[1]]];
              }
              case 4: {
                return v__inl3___input;
              }
            }
          }
          case 2: {
            {
              const __s = __predUInt8(v_n);
              switch (__s[0]) {
                case 3: {
                  const v_e = __s[1];
                  return [3, [3768445577, v_e]];
                }
                case 4: {
                  const v_m = __s[1];
                  {
                    const __s = __concat(v_acc, String(v_n));
                    switch (__s[0]) {
                      case 3: {
                        const v_e = __s[1];
                        return [3, [589989748, v_e]];
                      }
                      case 4: {
                        const v_s0 = __s[1];
                        {
                          const __s = __concat(v_s0, ",");
                          switch (__s[0]) {
                            case 3: {
                              const v_e = __s[1];
                              return [3, [589989748, v_e]];
                            }
                            case 4: {
                              const v_s1 = __s[1];
                              v_n = v_m;
                              v_acc = v_s1;
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
          }
        }
      }
    }
  };

  const main = (v__inl8_r =>
    (s => {
      switch (s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v__inl10_s = s[1];
          return [7, v__inl10_s, [5, [0]]];
        }
      }
    })(
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v__inl8_r[1];
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
            return __concat("right: ", v__inl8_r[1]);
          }
        }
      })(v__inl8_r)
    ))(v_countDown(255 & 0xFF, ""));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
