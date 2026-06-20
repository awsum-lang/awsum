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

  const v__inl51_xs = [13];
  const v__inl75_noElems = (s => {
    switch (s[0]) {
      case 13: {
        return [11];
      }
      case 14: {
        return [12, v__inl51_xs[1]];
      }
    }
  })(v__inl51_xs);
  const v__inl52_xs = [14, "a", [13]];
  const v__inl55_single = (s => {
    switch (s[0]) {
      case 13: {
        return [11];
      }
      case 14: {
        return [12, v__inl52_xs[1]];
      }
    }
  })(v__inl52_xs);
  const v__inl56_xs = [14, "a", [14, "b", [14, "c", [13]]]];
  const v__inl59_multi = (s => {
    switch (s[0]) {
      case 13: {
        return [11];
      }
      case 14: {
        return [12, v__inl56_xs[1]];
      }
    }
  })(v__inl56_xs);
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v__inl61__do_e_5 = s[1];
        return [3, v__inl61__do_e_5];
      }
      case 4: {
        const v__inl62_a = s[1];
        {
          const __s = (s => {
            switch (s[0]) {
              case 11: {
                return [4, "Nothing"];
              }
              case 12: {
                return __concat("Just ", v__inl55_single[1]);
              }
            }
          })(v__inl55_single);
          switch (__s[0]) {
            case 3: {
              const v__inl64__do_e_4 = __s[1];
              return [3, v__inl64__do_e_4];
            }
            case 4: {
              const v__inl65_b = __s[1];
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 11: {
                      return [4, "Nothing"];
                    }
                    case 12: {
                      return __concat("Just ", v__inl59_multi[1]);
                    }
                  }
                })(v__inl59_multi);
                switch (__s[0]) {
                  case 3: {
                    const v__inl67__do_e_3 = __s[1];
                    return [3, v__inl67__do_e_3];
                  }
                  case 4: {
                    const v__inl68_c = __s[1];
                    {
                      const __s = __concat(v__inl62_a, "|");
                      switch (__s[0]) {
                        case 3: {
                          const v__inl69__do_e_2 = __s[1];
                          return [3, v__inl69__do_e_2];
                        }
                        case 4: {
                          const v__inl70_s0 = __s[1];
                          {
                            const __s = __concat(v__inl70_s0, v__inl65_b);
                            switch (__s[0]) {
                              case 3: {
                                const v__inl71__do_e_1 = __s[1];
                                return [3, v__inl71__do_e_1];
                              }
                              case 4: {
                                const v__inl72_s1 = __s[1];
                                {
                                  const __s = __concat(v__inl72_s1, "|");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__inl73__do_e_0 = __s[1];
                                      return [3, v__inl73__do_e_0];
                                    }
                                    case 4: {
                                      const v__inl74_s2 = __s[1];
                                      return __concat(v__inl74_s2, v__inl68_c);
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
        case 11: {
          return [4, "Nothing"];
        }
        case 12: {
          return __concat("Just ", v__inl75_noElems[1]);
        }
      }
    })(v__inl75_noElems)
  );

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

  const v__inl78_x = v_res;
  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl78_x[1]];
          }
          case 4: {
            return [5, v__inl78_x[1]];
          }
        }
      })(v__inl78_x),
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
