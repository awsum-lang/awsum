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

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_26;
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
          v__k = [26, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_28;
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
          v__k = [28, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl95_fromNothing = [3, [24]];
  const v__inl69_fromJust = [4, "hi"];
  const v__inl70_xs = [14, "first", [14, "second", [13]]];
  const v__inl73_chained = (s => {
    switch (s[0]) {
      case 13: {
        return [3, [24]];
      }
      case 14: {
        return [4, v__inl70_xs[1]];
      }
    }
  })(v__inl70_xs);
  const v__inl92_msg = (s => {
    switch (s[0]) {
      case 3: {
        const v__inl76__do_e_6 = s[1];
        return [3, v__inl76__do_e_6];
      }
      case 4: {
        const v__inl77_a = s[1];
        {
          const __s = (s => {
            switch (s[0]) {
              case 3: {
                return [4, "Left Missing"];
              }
              case 4: {
                return __concat("Right ", v__inl69_fromJust[1]);
              }
            }
          })(v__inl69_fromJust);
          switch (__s[0]) {
            case 3: {
              const v__inl80__do_e_5 = __s[1];
              return [3, v__inl80__do_e_5];
            }
            case 4: {
              const v__inl81_b = __s[1];
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 3: {
                      return [4, "Left Missing"];
                    }
                    case 4: {
                      return __concat("Right ", v__inl73_chained[1]);
                    }
                  }
                })(v__inl73_chained);
                switch (__s[0]) {
                  case 3: {
                    const v__inl84__do_e_4 = __s[1];
                    return [3, v__inl84__do_e_4];
                  }
                  case 4: {
                    const v__inl85_c = __s[1];
                    {
                      const __s = __concat(v__inl77_a, "|");
                      switch (__s[0]) {
                        case 3: {
                          const v__inl86__do_e_3 = __s[1];
                          return [3, v__inl86__do_e_3];
                        }
                        case 4: {
                          const v__inl87_sep = __s[1];
                          {
                            const __s = __concat(v__inl87_sep, v__inl81_b);
                            switch (__s[0]) {
                              case 3: {
                                const v__inl88__do_e_2 = __s[1];
                                return [3, v__inl88__do_e_2];
                              }
                              case 4: {
                                const v__inl89_s1 = __s[1];
                                {
                                  const __s = __concat(v__inl89_s1, "|");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__inl90__do_e_1 = __s[1];
                                      return [3, v__inl90__do_e_1];
                                    }
                                    case 4: {
                                      const v__inl91_s2 = __s[1];
                                      return __concat(v__inl91_s2, v__inl85_c);
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
          return [4, "Left Missing"];
        }
        case 4: {
          return __concat("Right ", v__inl95_fromNothing[1]);
        }
      }
    })(v__inl95_fromNothing)
  );
  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl92_msg[1]];
          }
          case 4: {
            return [5, v__inl92_msg[1]];
          }
        }
      })(v__inl92_msg),
      [27]
    ),
    [25]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
