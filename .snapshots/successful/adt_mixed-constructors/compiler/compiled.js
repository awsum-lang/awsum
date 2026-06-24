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
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$inl3$token = [24, "hello"];
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__8 = s[1];
        return [3, v_$do__e__8];
      }
      case 4: {
        const v_a = s[1];
        const v_$inl6$token = [26];
        {
          const __s = (s => {
            switch (s[0]) {
              case 24: {
                return __concat("word:", v_$inl6$token[1]);
              }
              case 25: {
                return __concat("num:", v_$inl6$token[1]);
              }
              case 26: {
                return [4, ","];
              }
              case 27: {
                return [4, "<eof>"];
              }
            }
          })(v_$inl6$token);
          switch (__s[0]) {
            case 3: {
              const v_$do__e__7 = __s[1];
              return [3, v_$do__e__7];
            }
            case 4: {
              const v_b = __s[1];
              const v_$inl9$token = [25, "42"];
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 24: {
                      return __concat("word:", v_$inl9$token[1]);
                    }
                    case 25: {
                      return __concat("num:", v_$inl9$token[1]);
                    }
                    case 26: {
                      return [4, ","];
                    }
                    case 27: {
                      return [4, "<eof>"];
                    }
                  }
                })(v_$inl9$token);
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__6 = __s[1];
                    return [3, v_$do__e__6];
                  }
                  case 4: {
                    const v_c = __s[1];
                    const v_$inl12$token = [27];
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 24: {
                            return __concat("word:", v_$inl12$token[1]);
                          }
                          case 25: {
                            return __concat("num:", v_$inl12$token[1]);
                          }
                          case 26: {
                            return [4, ","];
                          }
                          case 27: {
                            return [4, "<eof>"];
                          }
                        }
                      })(v_$inl12$token);
                      switch (__s[0]) {
                        case 3: {
                          const v_$do__e__5 = __s[1];
                          return [3, v_$do__e__5];
                        }
                        case 4: {
                          const v_d = __s[1];
                          {
                            const __s = __concat(v_a, " ");
                            switch (__s[0]) {
                              case 3: {
                                const v_$do__e__4 = __s[1];
                                return [3, v_$do__e__4];
                              }
                              case 4: {
                                const v_ab = __s[1];
                                {
                                  const __s = __concat(v_ab, v_b);
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$do__e__3 = __s[1];
                                      return [3, v_$do__e__3];
                                    }
                                    case 4: {
                                      const v_abc = __s[1];
                                      {
                                        const __s = __concat(v_abc, " ");
                                        switch (__s[0]) {
                                          case 3: {
                                            const v_$do__e__2 = __s[1];
                                            return [3, v_$do__e__2];
                                          }
                                          case 4: {
                                            const v_abcs = __s[1];
                                            {
                                              const __s = __concat(v_abcs, v_c);
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v_$do__e__1 = __s[1];
                                                  return [3, v_$do__e__1];
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
                                                        const v_$do__e__0 = __s[1];
                                                        return [3, v_$do__e__0];
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
          return __concat("word:", v_$inl3$token[1]);
        }
        case 25: {
          return __concat("num:", v_$inl3$token[1]);
        }
        case 26: {
          return [4, ","];
        }
        case 27: {
          return [4, "<eof>"];
        }
      }
    })(v_$inl3$token)
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 28: {
          return v_$x;
        }
        case 29: {
          const v_$pk__29 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__29;
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
          v_$k = [29, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 30: {
          return v_$x;
        }
        case 31: {
          const v_$pk__31 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__31;
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
          v_$k = [31, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl15$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl15$x[1]];
          }
          case 4: {
            return [5, v_$inl15$x[1]];
          }
        }
      })(v_$inl15$x),
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
