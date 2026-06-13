"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

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

  const v_buildRight = (v_depth, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_depth, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_acc];
          }
          case 2: {
            {
              const __s = __predInt32(v_depth);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_5 = __s[1];
                  return [3, v__do_e_5];
                }
                case 4: {
                  const v_d = __s[1];
                  v_acc = [25, [24], v_depth, v_acc];
                  v_depth = v_d;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_buildLeft = (v_depth, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_depth, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_acc];
          }
          case 2: {
            {
              const __s = __predInt32(v_depth);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_4 = __s[1];
                  return [3, v__do_e_4];
                }
                case 4: {
                  const v_d = __s[1];
                  v_acc = [25, v_acc, v_depth, [24]];
                  v_depth = v_d;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__scc_deepestLeftA_deepestLeftB_deepestLeftC = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 26: {
          const v_lastV = v__args[1];
          const v_t = v__args[2];
          switch (v_t[0]) {
            case 24: {
              return v_lastV;
            }
            case 25: {
              v__args = (v__args[0] = 27, v__args[1] = v_t[2], v__args[2] = v_t[1], v__args);
              continue;
            }
          }
        }
        case 27: {
          const v_lastV = v__args[1];
          const v_t = v__args[2];
          switch (v_t[0]) {
            case 24: {
              return v_lastV;
            }
            case 25: {
              v__args = (v__args[0] = 28, v__args[1] = v_t[2], v__args[2] = v_t[1], v__args);
              continue;
            }
          }
        }
        case 28: {
          const v_lastV = v__args[1];
          const v_t = v__args[2];
          switch (v_t[0]) {
            case 24: {
              return v_lastV;
            }
            case 25: {
              v__args = (v__args[0] = 26, v__args[1] = v_t[2], v__args[2] = v_t[1], v__args);
              continue;
            }
          }
        }
      }
    }
  };

  const v__scc__apply_mirror__cps_mirror = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 32: {
          const v__k = v__args[1];
          const v__x = v__args[2];
          switch (v__k[0]) {
            case 29: {
              return v__x;
            }
            case 31: {
              const v__pk_31 = v__k[1];
              v__args = (v__args[0] = 32, v__args[1] = v__pk_31, v__args[2] = (v__k[0] = 25, v__k[1] = v__k[2], v__k[2] = v__k[3], v__k[3] = v__x, v__k), v__args);
              continue;
            }
            case 30: {
              const v_l = v__k[2];
              v__args = (v__args[0] = 33, v__args[1] = v_l, v__args[2] = (v__k[0] = 31, v__k[2] = v__x, v__k), v__args);
              continue;
            }
          }
        }
        case 33: {
          const v_t = v__args[1];
          const v__k = v__args[2];
          switch (v_t[0]) {
            case 24: {
              v__args = (v__args[0] = 32, v__args[2] = v__args[1], v__args[1] = v__k, v__args);
              continue;
            }
            case 25: {
              v__args = (v__args[0] = 33, v__args[1] = v_t[3], v__args[2] = [
                30,
                v__k,
                v_t[1],
                v_t[2]
              ], v__args);
              continue;
            }
          }
        }
      }
    }
  };

  const v_mirrorN = (v_times, v_t) => {
    while (true) {
      {
        const __s = __eqInt32(v_times, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_t];
          }
          case 2: {
            {
              const __s = __predInt32(v_times);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_6 = __s[1];
                  return [3, v__do_e_6];
                }
                case 4: {
                  const v_m = __s[1];
                  v_times = v_m;
                  v_t = v__scc__apply_mirror__cps_mirror([33, v_t, [29]]);
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_runDemo = (v__inl5_depth =>
    (() => {
      let v__inl7_scrut;
      $join6: {
        const __s = v_buildLeft(v__inl5_depth, [24]);
        switch (__s[0]) {
          case 3: {
            const v__inl1__do_e_3 = __s[1];
            return [3, v__inl1__do_e_3];
          }
          case 4: {
            const v__inl2_l = __s[1];
            v__inl7_scrut = (s => {
              switch (s[0]) {
                case 3: {
                  const v__inl3__do_e_2 = s[1];
                  return [3, v__inl3__do_e_2];
                }
                case 4: {
                  const v__inl4_r = s[1];
                  return [4, [25, v__inl2_l, 0 | 0, v__inl4_r]];
                }
              }
            })(v_buildRight(v__inl5_depth, [24]));
            break $join6;
          }
        }
      }
      switch (v__inl7_scrut[0]) {
        case 3: {
          return v__inl7_scrut;
        }
        case 4: {
          {
            const __s = v_mirrorN(500 | 0, v__inl7_scrut[1]);
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                return [3, v__do_e_0];
              }
              case 4: {
                const v_mirrored = __s[1];
                return [
                  4,
                  v__scc_deepestLeftA_deepestLeftB_deepestLeftC(
                    [26, 0 | 0, v_mirrored]
                  )
                ];
              }
            }
          }
        }
      }
    })())(10000 | 0);

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "UnderflowError", [5, [0]]];
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
