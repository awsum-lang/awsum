"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

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

  const v_countTail = (v_remaining, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_remaining, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_acc];
          }
          case 2: {
            {
              const __s = __succInt32(v_acc);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_3 = __s[1];
                  return [3, [882564211, v__do_e_3]];
                }
                case 4: {
                  const v_a = __s[1];
                  {
                    const __s = __predInt32(v_remaining);
                    switch (__s[0]) {
                      case 3: {
                        const v__do_e_2 = __s[1];
                        return [3, [3768445577, v__do_e_2]];
                      }
                      case 4: {
                        const v_r = __s[1];
                        v_remaining = v_r;
                        v_acc = v_a;
                        continue;
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

  const v__scc_spinA_spinB_spinC = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 8: {
          const v_remaining = v__args[1];
          const v_acc = v__args[2];
          {
            const __s = __eqInt32(v_remaining, 0 | 0);
            switch (__s[0]) {
              case 1: {
                return [4, v_acc];
              }
              case 2: {
                {
                  const __s = __succInt32(v_acc);
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_9 = __s[1];
                      return [3, [882564211, v__do_e_9]];
                    }
                    case 4: {
                      const v_a = __s[1];
                      {
                        const __s = __predInt32(v_remaining);
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_8 = __s[1];
                            return [3, [3768445577, v__do_e_8]];
                          }
                          case 4: {
                            const v_r = __s[1];
                            v__args = (v__args[0] = 9, v__args[1] = v_r, v__args[2] = v_a, v__args);
                            continue;
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
        case 9: {
          const v_remaining = v__args[1];
          const v_acc = v__args[2];
          {
            const __s = __eqInt32(v_remaining, 0 | 0);
            switch (__s[0]) {
              case 1: {
                return [4, v_acc];
              }
              case 2: {
                {
                  const __s = __succInt32(v_acc);
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_11 = __s[1];
                      return [3, [882564211, v__do_e_11]];
                    }
                    case 4: {
                      const v_a = __s[1];
                      {
                        const __s = __predInt32(v_remaining);
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_10 = __s[1];
                            return [3, [3768445577, v__do_e_10]];
                          }
                          case 4: {
                            const v_r = __s[1];
                            v__args = (v__args[0] = 10, v__args[1] = v_r, v__args[2] = v_a, v__args);
                            continue;
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
        case 10: {
          const v_remaining = v__args[1];
          const v_acc = v__args[2];
          {
            const __s = __eqInt32(v_remaining, 0 | 0);
            switch (__s[0]) {
              case 1: {
                return [4, v_acc];
              }
              case 2: {
                {
                  const __s = __succInt32(v_acc);
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_13 = __s[1];
                      return [3, [882564211, v__do_e_13]];
                    }
                    case 4: {
                      const v_a = __s[1];
                      {
                        const __s = __predInt32(v_remaining);
                        switch (__s[0]) {
                          case 3: {
                            const v__do_e_12 = __s[1];
                            return [3, [3768445577, v__do_e_12]];
                          }
                          case 4: {
                            const v_r = __s[1];
                            v__args = (v__args[0] = 8, v__args[1] = v_r, v__args[2] = v_a, v__args);
                            continue;
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

  const v__apply_descend = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 11: {
          return v__x;
        }
        case 12: {
          const v__pk_12 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_12;
              continue;
            }
            case 4: {
              v__x = (() => {
                const v__inl3___input = __succInt32(v__x[1]);
                return (s => {
                  switch (s[0]) {
                    case 3: {
                      return (v__k[0] = 3, v__k[1] = [
                        882564211,
                        v__inl3___input[1]
                      ], v__k);
                    }
                    case 4: {
                      return v__inl3___input;
                    }
                  }
                })(v__inl3___input);
              })();
              v__k = v__pk_12;
              continue;
            }
          }
        }
      }
    }
  };

  const v__cps_descend = (v_n, v__k) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v__apply_descend(v__k, [4, 0 | 0]);
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_7 = __s[1];
                  return v__apply_descend(v__k, [3, [3768445577, v__do_e_7]]);
                }
                case 4: {
                  const v_p = __s[1];
                  v_n = v_p;
                  v__k = [12, v__k];
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_descendN = (v_rounds, v_depth) => {
    while (true) {
      {
        const __s = __eqInt32(v_rounds, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_depth];
          }
          case 2: {
            {
              const __s = v__cps_descend(v_depth, [11]);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_5 = __s[1];
                  return [3, v__do_e_5];
                }
                case 4: {
                  const v_d = __s[1];
                  {
                    const __s = __predInt32(v_rounds);
                    switch (__s[0]) {
                      case 3: {
                        const v__do_e_4 = __s[1];
                        return [3, [3768445577, v__do_e_4]];
                      }
                      case 4: {
                        const v_r = __s[1];
                        v_rounds = v_r;
                        v_depth = v_d;
                        continue;
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

  const v_runDemo = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_1 = s[1];
        return [3, v__do_e_1];
      }
      case 4: {
        const v_tailed = s[1];
        {
          const __s = v_descendN(25 | 0, v_tailed);
          switch (__s[0]) {
            case 3: {
              const v__do_e_0 = __s[1];
              return [3, v__do_e_0];
            }
            case 4: {
              const v_looped = __s[1];
              return v__scc_spinA_spinB_spinC([8, v_looped, 0 | 0]);
            }
          }
        }
      }
    }
  })(v_countTail(5000000 | 0, 0 | 0));

  const main = (s => {
    switch (s[0]) {
      case 3: {
        const v_e = s[1];
        return [
          7,
          (s => {
            switch (s[0]) {
              case 882564211: {
                return "OverflowError";
              }
              case 3768445577: {
                return "UnderflowError";
              }
            }
          })(v_e),
          [5, [0]]
        ];
      }
      case 4: {
        const v_n = s[1];
        return [7, String(v_n), [5, [0]]];
      }
    }
  })(v_runDemo);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
