"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

  const __lengthCodePoints = s => Array.from(s).length >>> 0;

  const __lengthUtf16CodeUnits = s => s.length >>> 0;

  const __lengthUtf8Bytes = s => new TextEncoder().encode(s).length >>> 0;

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

  const v_check = (v_expected, v_actual, v_label) => {
    {
      const __s = __eqUInt32(v_expected, v_actual);
      switch (__s[0]) {
        case 1: {
          return __concat(v_label, "=ok");
        }
        case 2: {
          {
            const __s = __concat(v_label, "=FAIL(expected=");
            switch (__s[0]) {
              case 3: {
                const v__do_e_3 = __s[1];
                return [3, v__do_e_3];
              }
              case 4: {
                const v_s0 = __s[1];
                {
                  const __s = __concat(v_s0, String(v_expected));
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_2 = __s[1];
                      return [3, v__do_e_2];
                    }
                    case 4: {
                      const v_s1 = __s[1];
                      {
                        const __s = __concat(v_s1, ", got=");
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_1 = __s[1];
                            return [3, v__do_e_1];
                          }
                          case 4: {
                            const v_s2 = __s[1];
                            {
                              const __s = __concat(v_s2, String(v_actual));
                              switch (__s[0]) {
                                case 3: {
                                  const v__do_e_0 = __s[1];
                                  return [3, v__do_e_0];
                                }
                                case 4: {
                                  const v_s3 = __s[1];
                                  return __concat(v_s3, ")");
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
  };

  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_9 = s[1];
        return [3, v__do_e_9];
      }
      case 4: {
        const v_a = s[1];
        {
          const __s = v_check(
            2 >>> 0,
            __lengthUtf16CodeUnits("🔥"),
            "lengthUtf16CodeUnits"
          );
          switch (__s[0]) {
            case 3: {
              const v__do_e_8 = __s[1];
              return [3, v__do_e_8];
            }
            case 4: {
              const v_b = __s[1];
              {
                const __s = v_check(
                  4 >>> 0,
                  __lengthUtf8Bytes("🔥"),
                  "lengthUtf8Bytes"
                );
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_7 = __s[1];
                    return [3, v__do_e_7];
                  }
                  case 4: {
                    const v_c = __s[1];
                    {
                      const __s = __concat(v_a, ", ");
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_6 = __s[1];
                          return [3, v__do_e_6];
                        }
                        case 4: {
                          const v_s0 = __s[1];
                          {
                            const __s = __concat(v_s0, v_b);
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_5 = __s[1];
                                return [3, v__do_e_5];
                              }
                              case 4: {
                                const v_s1 = __s[1];
                                {
                                  const __s = __concat(v_s1, ", ");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_4 = __s[1];
                                      return [3, v__do_e_4];
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
        }
      }
    }
  })(v_check(1 >>> 0, __lengthCodePoints("🔥"), "lengthCodePoints"));

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
          const v__pk_21 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_21;
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
          v__k = [21, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 22: {
          return v__x;
        }
        case 23: {
          const v__pk_23 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_23;
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
          v__k = [23, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (v__inl3_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl3_x[1]];
            }
            case 4: {
              return [5, v__inl3_x[1]];
            }
          }
        })(v__inl3_x))(v_res),
      [22]
    ),
    [20]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
