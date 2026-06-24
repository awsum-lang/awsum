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
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$inl3$r = __parseInt32("41");
  const main = (() => {
    let v_$inl16$scrut;
    $join15: {
      const __s = (s => {
        switch (s[0]) {
          case 3: {
            return [4, "err"];
          }
          case 4: {
            return __concat("ok:", String(v_$inl3$r[1]));
          }
        }
      })(v_$inl3$r);
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_a = __s[1];
          const v_$inl6$r = __parseInt32("x");
          v_$inl16$scrut = (s => {
            switch (s[0]) {
              case 3: {
                const v_$do__e__5 = s[1];
                return [3, v_$do__e__5];
              }
              case 4: {
                const v_b = s[1];
                const v_$inl9$r = __parseInt32("43");
                {
                  const __s = (s => {
                    switch (s[0]) {
                      case 3: {
                        return [4, "err"];
                      }
                      case 4: {
                        return __concat("ok:", String(v_$inl9$r[1]));
                      }
                    }
                  })(v_$inl9$r);
                  switch (__s[0]) {
                    case 3: {
                      const v_$do__e__4 = __s[1];
                      return [3, v_$do__e__4];
                    }
                    case 4: {
                      const v_c = __s[1];
                      const v_$inl12$r = __parseInt32("44");
                      {
                        const __s = (s => {
                          switch (s[0]) {
                            case 3: {
                              return [4, "err"];
                            }
                            case 4: {
                              return __concat("ok:", String(v_$inl12$r[1]));
                            }
                          }
                        })(v_$inl12$r);
                        switch (__s[0]) {
                          case 3: {
                            const v_$do__e__3 = __s[1];
                            return [3, v_$do__e__3];
                          }
                          case 4: {
                            const v_d = __s[1];
                            {
                              const __s = __concat(v_a, v_b);
                              switch (__s[0]) {
                                case 3: {
                                  const v_$do__e__2 = __s[1];
                                  return [3, v_$do__e__2];
                                }
                                case 4: {
                                  const v_s0 = __s[1];
                                  {
                                    const __s = __concat(v_s0, v_c);
                                    switch (__s[0]) {
                                      case 3: {
                                        const v_$do__e__1 = __s[1];
                                        return [3, v_$do__e__1];
                                      }
                                      case 4: {
                                        const v_s1 = __s[1];
                                        {
                                          const __s = __concat(v_s1, v_d);
                                          switch (__s[0]) {
                                            case 3: {
                                              const v_$do__e__0 = __s[1];
                                              return [3, v_$do__e__0];
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
                  return __concat("ok:", String(v_$inl6$r[1]));
                }
              }
            })(v_$inl6$r)
          );
          break $join15;
        }
      }
    }
    switch (v_$inl16$scrut[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        return [7, v_$inl16$scrut[1], [5, [0]]];
      }
    }
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
