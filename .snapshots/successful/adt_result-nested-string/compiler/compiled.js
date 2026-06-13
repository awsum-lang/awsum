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

  const main = (() => {
    let v__inl12_scrut;
    $join11: {
      const __s = __concat(
        (s => {
          switch (s[0]) {
            case 24: {
              const v__inl1___p0 = s[1];
              return v__inl1___p0[1];
            }
            case 25: {
              const v__inl2___p0 = s[1];
              return v__inl2___p0[1];
            }
          }
        })([24, [24, "1"]]),
        ","
      );
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s0 = __s[1];
          v__inl12_scrut = (s => {
            switch (s[0]) {
              case 3: {
                const v__do_e_3 = s[1];
                return [3, v__do_e_3];
              }
              case 4: {
                const v_s1 = s[1];
                {
                  const __s = __concat(v_s1, ",");
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_2 = __s[1];
                      return [3, v__do_e_2];
                    }
                    case 4: {
                      const v_s2 = __s[1];
                      {
                        const __s = __concat(
                          v_s2,
                          (s => {
                            switch (s[0]) {
                              case 24: {
                                const v__inl5___p0 = s[1];
                                return v__inl5___p0[1];
                              }
                              case 25: {
                                const v__inl6___p0 = s[1];
                                return v__inl6___p0[1];
                              }
                            }
                          })([25, [24, "3"]])
                        );
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_1 = __s[1];
                            return [3, v__do_e_1];
                          }
                          case 4: {
                            const v_s3 = __s[1];
                            {
                              const __s = __concat(v_s3, ",");
                              switch (__s[0]) {
                                case 3: {
                                  const v__do_e_0 = __s[1];
                                  return [3, v__do_e_0];
                                }
                                case 4: {
                                  const v_s4 = __s[1];
                                  return __concat(
                                    v_s4,
                                    (s => {
                                      switch (s[0]) {
                                        case 24: {
                                          const v__inl7___p0 = s[1];
                                          return v__inl7___p0[1];
                                        }
                                        case 25: {
                                          const v__inl8___p0 = s[1];
                                          return v__inl8___p0[1];
                                        }
                                      }
                                    })([25, [25, "4"]])
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
          })(
            __concat(
              v_s0,
              (s => {
                switch (s[0]) {
                  case 24: {
                    const v__inl3___p0 = s[1];
                    return v__inl3___p0[1];
                  }
                  case 25: {
                    const v__inl4___p0 = s[1];
                    return v__inl4___p0[1];
                  }
                }
              })([24, [25, "2"]])
            )
          );
          break $join11;
        }
      }
    }
    switch (v__inl12_scrut[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        return [7, v__inl12_scrut[1], [5, [0]]];
      }
    }
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
