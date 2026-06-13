"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predUInt8 = x => x === 0 ? [3, [17]] : [4, x - 1 & 0xFF];

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

  const v_minUInt8 = 0 & 0xFF;

  const v_maxUInt8 = 255 & 0xFF;

  const main = (v__inl3_r =>
    (() => {
      let v__inl13_scrut;
      $join12: {
        const __s = (s => {
          switch (s[0]) {
            case 3: {
              return __concat("underflow: ", "UnderflowError");
            }
            case 4: {
              return __concat("ok: ", String(v__inl3_r[1]));
            }
          }
        })(v__inl3_r);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl13_scrut = (v__inl6_r =>
              (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_4 = s[1];
                    return [3, v__do_e_4];
                  }
                  case 4: {
                    const v_b = s[1];
                    const v__inl9_r = __predUInt8(v_maxUInt8);
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 3: {
                            return __concat("underflow: ", "UnderflowError");
                          }
                          case 4: {
                            return __concat("ok: ", String(v__inl9_r[1]));
                          }
                        }
                      })(v__inl9_r);
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_3 = __s[1];
                          return [3, v__do_e_3];
                        }
                        case 4: {
                          const v_c = __s[1];
                          {
                            const __s = __concat(v_a, ", ");
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
                                        const __s = __concat(v_s1, ", ");
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_0 = __s[1];
                                            return [3, v__do_e_0];
                                          }
                                          case 4: {
                                            const v_s2 = __s[1];
                                            return __concat(v_s2, v_c);
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
                    case 3: {
                      return __concat("underflow: ", "UnderflowError");
                    }
                    case 4: {
                      return __concat("ok: ", String(v__inl6_r[1]));
                    }
                  }
                })(v__inl6_r)
              ))([4, 0 & 0xFF]);
            break $join12;
          }
        }
      }
      switch (v__inl13_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl13_scrut[1], [5, [0]]];
        }
      }
    })())(__predUInt8(v_minUInt8));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
