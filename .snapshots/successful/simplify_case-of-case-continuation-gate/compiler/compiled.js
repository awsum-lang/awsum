"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __parseInt32 = s => {
    if (!/^-?[0-9]+$/.test(s)) {
      return [3, [22]];
    }
    const n = Number(s);
    if (n < -2147483648 || n > 2147483647) {
      return [3, [22]];
    }
    return [4, n | 0];
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

  const main = (v__inl3_r =>
    (() => {
      let v__inl16_scrut;
      $join15: {
        const __s = (s => {
          switch (s[0]) {
            case 3: {
              return [4, "err"];
            }
            case 4: {
              return __concat("ok:", String(v__inl3_r[1]));
            }
          }
        })(v__inl3_r);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl16_scrut = (v__inl6_r =>
              (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_5 = s[1];
                    return [3, v__do_e_5];
                  }
                  case 4: {
                    const v_b = s[1];
                    const v__inl9_r = __parseInt32("43");
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 3: {
                            return [4, "err"];
                          }
                          case 4: {
                            return __concat("ok:", String(v__inl9_r[1]));
                          }
                        }
                      })(v__inl9_r);
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_4 = __s[1];
                          return [3, v__do_e_4];
                        }
                        case 4: {
                          const v_c = __s[1];
                          const v__inl12_r = __parseInt32("44");
                          {
                            const __s = (s => {
                              switch (s[0]) {
                                case 3: {
                                  return [4, "err"];
                                }
                                case 4: {
                                  return __concat("ok:", String(v__inl12_r[1]));
                                }
                              }
                            })(v__inl12_r);
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_3 = __s[1];
                                return [3, v__do_e_3];
                              }
                              case 4: {
                                const v_d = __s[1];
                                {
                                  const __s = __concat(v_a, v_b);
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_2 = __s[1];
                                      return [3, v__do_e_2];
                                    }
                                    case 4: {
                                      const v_s0 = __s[1];
                                      {
                                        const __s = __concat(v_s0, v_c);
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_1 = __s[1];
                                            return [3, v__do_e_1];
                                          }
                                          case 4: {
                                            const v_s1 = __s[1];
                                            {
                                              const __s = __concat(v_s1, v_d);
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__do_e_0 = __s[1];
                                                  return [3, v__do_e_0];
                                                }
                                                case 4: {
                                                  const v_s2 = __s[1];
                                                  return [4, v_s2];
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
                    }
                  }
                }
              })(
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [4, "err"];
                    }
                    case 4: {
                      return __concat("ok:", String(v__inl6_r[1]));
                    }
                  }
                })(v__inl6_r)
              ))(__parseInt32("x"));
            break $join15;
          }
        }
      }
      switch (v__inl16_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl16_scrut[1], [5, [0]]];
        }
      }
    })())(__parseInt32("41"));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
