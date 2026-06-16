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

  const v_res = (v__inl3_token =>
    (s => {
      switch (s[0]) {
        case 3: {
          const v__do_e_8 = s[1];
          return [3, v__do_e_8];
        }
        case 4: {
          const v_a = s[1];
          const v__inl6_token = [26];
          {
            const __s = (s => {
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
            })(v__inl6_token);
            switch (__s[0]) {
              case 3: {
                const v__do_e_7 = __s[1];
                return [3, v__do_e_7];
              }
              case 4: {
                const v_b = __s[1];
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
                                                          return [3, v__do_e_0];
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
          }
        }
      }
    })(
      (s => {
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
      })(v__inl3_token)
    ))([24, "hello"]);

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          const v__pk_29 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_29;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_0(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_0(
            v__k,
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [29, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 30: {
          return v__x;
        }
        case 31: {
          const v__pk_31 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_31;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_4(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [31, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (v__inl15_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl15_x[1]];
            }
            case 4: {
              return [5, v__inl15_x[1]];
            }
          }
        })(v__inl15_x))(v_res),
      [30]
    ),
    [28]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
