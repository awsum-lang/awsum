"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const main = (v__inl3_token =>
    (() => {
      let v__inl16_scrut;
      $join15: {
        const __s = (s => {
          switch (s[0]) {
            case 24: {
              return __concat("word:", v__inl3_token[1]);
            }
            case 25: {
              return __concat("num:", v__inl3_token[1]);
            }
            case 26: {
              return [4, ","];
            }
            case 27: {
              return [4, "<eof>"];
            }
          }
        })(v__inl3_token);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl16_scrut = (v__inl6_token =>
              (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_7 = s[1];
                    return [3, v__do_e_7];
                  }
                  case 4: {
                    const v_b = s[1];
                    const v__inl9_token = [25, "42"];
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 24: {
                            return __concat("word:", v__inl9_token[1]);
                          }
                          case 25: {
                            return __concat("num:", v__inl9_token[1]);
                          }
                          case 26: {
                            return [4, ","];
                          }
                          case 27: {
                            return [4, "<eof>"];
                          }
                        }
                      })(v__inl9_token);
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_6 = __s[1];
                          return [3, v__do_e_6];
                        }
                        case 4: {
                          const v_c = __s[1];
                          const v__inl12_token = [27];
                          {
                            const __s = (s => {
                              switch (s[0]) {
                                case 24: {
                                  return __concat("word:", v__inl12_token[1]);
                                }
                                case 25: {
                                  return __concat("num:", v__inl12_token[1]);
                                }
                                case 26: {
                                  return [4, ","];
                                }
                                case 27: {
                                  return [4, "<eof>"];
                                }
                              }
                            })(v__inl12_token);
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_5 = __s[1];
                                return [3, v__do_e_5];
                              }
                              case 4: {
                                const v_d = __s[1];
                                {
                                  const __s = __concat(v_a, " ");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_4 = __s[1];
                                      return [3, v__do_e_4];
                                    }
                                    case 4: {
                                      const v_ab = __s[1];
                                      {
                                        const __s = __concat(v_ab, v_b);
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_3 = __s[1];
                                            return [3, v__do_e_3];
                                          }
                                          case 4: {
                                            const v_abc = __s[1];
                                            {
                                              const __s = __concat(v_abc, " ");
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__do_e_2 = __s[1];
                                                  return [3, v__do_e_2];
                                                }
                                                case 4: {
                                                  const v_abcs = __s[1];
                                                  {
                                                    const __s = __concat(
                                                      v_abcs,
                                                      v_c
                                                    );
                                                    switch (__s[0]) {
                                                      case 3: {
                                                        const v__do_e_1 = __s[1];
                                                        return [3, v__do_e_1];
                                                      }
                                                      case 4: {
                                                        const v_abcsc = __s[1];
                                                        {
                                                          const __s = __concat(
                                                            v_abcsc,
                                                            " "
                                                          );
                                                          switch (__s[0]) {
                                                            case 3: {
                                                              const v__do_e_0 = __s[1];
                                                              return [
                                                                3,
                                                                v__do_e_0
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v_abcscd = __s[1];
                                                              return __concat(
                                                                v_abcscd,
                                                                v_d
                                                              );
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
                          }
                        }
                      }
                    }
                  }
                }
              })(
                (s => {
                  switch (s[0]) {
                    case 24: {
                      return __concat("word:", v__inl6_token[1]);
                    }
                    case 25: {
                      return __concat("num:", v__inl6_token[1]);
                    }
                    case 26: {
                      return [4, ","];
                    }
                    case 27: {
                      return [4, "<eof>"];
                    }
                  }
                })(v__inl6_token)
              ))([26]);
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
    })())([24, "hello"]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
