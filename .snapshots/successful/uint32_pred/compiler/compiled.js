"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __predUInt32 = x => x === 0 ? [3, [17]] : [4, x - 1 >>> 0];

  const v_showUnderflowError = v__wild0 => "UnderflowError";

  const v_runIO = v_io => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            {
              const __s = __print(v_s);
              switch (__s[0]) {
                case 0: {
                  const __t0 = v_next;
                  v_io = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_render = v_r => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return __concat("underflow: ", v_showUnderflowError(v_e));
        }
        case 4: {
          const v_v = __s[1];
          return __concat("ok: ", String(v_v));
        }
      }
    }
  };

  const v_minUInt32 = 0 >>> 0;

  const v_maxUInt32 = 4294967295 >>> 0;

  const v__let_13 = v_res => {
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
  };

  const main = v__let_13(
    (s => {
      switch (s[0]) {
        case 3: {
          const v__do_e_8 = s[1];
          return [3, v__do_e_8];
        }
        case 4: {
          const v_a = s[1];
          return (s => {
            switch (s[0]) {
              case 3: {
                const v__do_e_7 = s[1];
                return [3, v__do_e_7];
              }
              case 4: {
                const v_b = s[1];
                return (s => {
                  switch (s[0]) {
                    case 3: {
                      const v__do_e_6 = s[1];
                      return [3, v__do_e_6];
                    }
                    case 4: {
                      const v_c = s[1];
                      return (s => {
                        switch (s[0]) {
                          case 3: {
                            const v__do_e_5 = s[1];
                            return [3, v__do_e_5];
                          }
                          case 4: {
                            const v_d = s[1];
                            return (s => {
                              switch (s[0]) {
                                case 3: {
                                  const v__do_e_4 = s[1];
                                  return [3, v__do_e_4];
                                }
                                case 4: {
                                  const v_s0 = s[1];
                                  return (s => {
                                    switch (s[0]) {
                                      case 3: {
                                        const v__do_e_3 = s[1];
                                        return [3, v__do_e_3];
                                      }
                                      case 4: {
                                        const v_s1 = s[1];
                                        return (s => {
                                          switch (s[0]) {
                                            case 3: {
                                              const v__do_e_2 = s[1];
                                              return [3, v__do_e_2];
                                            }
                                            case 4: {
                                              const v_s2 = s[1];
                                              return (s => {
                                                switch (s[0]) {
                                                  case 3: {
                                                    const v__do_e_1 = s[1];
                                                    return [3, v__do_e_1];
                                                  }
                                                  case 4: {
                                                    const v_s3 = s[1];
                                                    return (s => {
                                                      switch (s[0]) {
                                                        case 3: {
                                                          const v__do_e_0 = s[1];
                                                          return [3, v__do_e_0];
                                                        }
                                                        case 4: {
                                                          const v_s4 = s[1];
                                                          return __concat(
                                                            v_s4,
                                                            v_d
                                                          );
                                                        }
                                                      }
                                                    })(__concat(v_s3, ", "));
                                                  }
                                                }
                                              })(__concat(v_s2, v_c));
                                            }
                                          }
                                        })(__concat(v_s1, ", "));
                                      }
                                    }
                                  })(__concat(v_s0, v_b));
                                }
                              }
                            })(__concat(v_a, ", "));
                          }
                        }
                      })(v_render(__predUInt32(v_maxUInt32)));
                    }
                  }
                })(v_render(__predUInt32(2147483648 >>> 0)));
              }
            }
          })(v_render(__predUInt32(1 >>> 0)));
        }
      }
    })(v_render(__predUInt32(v_minUInt32)))
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
