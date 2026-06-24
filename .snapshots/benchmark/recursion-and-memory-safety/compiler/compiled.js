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
          const v_$inl0$eff = __print(v_io[1]);
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
                  const v_$do__e__5 = __s[1];
                  return [3, v_$do__e__5];
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
                  const v_$do__e__4 = __s[1];
                  return [3, v_$do__e__4];
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

  const v_$scc$deepestLeftA__deepestLeftB__deepestLeftC = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 26: {
          const v_lastV = v_$args[1];
          const v_t = v_$args[2];
          switch (v_t[0]) {
            case 24: {
              return v_lastV;
            }
            case 25: {
              v_$args = (v_$args[0] = 27, v_$args[1] = v_t[2], v_$args[2] = v_t[1], v_$args);
              continue;
            }
          }
        }
        case 27: {
          const v_lastV = v_$args[1];
          const v_t = v_$args[2];
          switch (v_t[0]) {
            case 24: {
              return v_lastV;
            }
            case 25: {
              v_$args = (v_$args[0] = 28, v_$args[1] = v_t[2], v_$args[2] = v_t[1], v_$args);
              continue;
            }
          }
        }
        case 28: {
          const v_lastV = v_$args[1];
          const v_t = v_$args[2];
          switch (v_t[0]) {
            case 24: {
              return v_lastV;
            }
            case 25: {
              v_$args = (v_$args[0] = 26, v_$args[1] = v_t[2], v_$args[2] = v_t[1], v_$args);
              continue;
            }
          }
        }
      }
    }
  };

  const v_$scc$$apply$mirror__$cps$mirror = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 32: {
          const v_$k = v_$args[1];
          const v_$x = v_$args[2];
          switch (v_$k[0]) {
            case 29: {
              return v_$x;
            }
            case 31: {
              const v_$pk__31 = v_$k[1];
              v_$args = (v_$args[0] = 32, v_$args[1] = v_$pk__31, v_$args[2] = (v_$k[0] = 25, v_$k[1] = v_$k[2], v_$k[2] = v_$k[3], v_$k[3] = v_$x, v_$k), v_$args);
              continue;
            }
            case 30: {
              const v_l = v_$k[2];
              v_$args = (v_$args[0] = 33, v_$args[1] = v_l, v_$args[2] = (v_$k[0] = 31, v_$k[2] = v_$x, v_$k), v_$args);
              continue;
            }
          }
        }
        case 33: {
          const v_t = v_$args[1];
          const v_$k = v_$args[2];
          switch (v_t[0]) {
            case 24: {
              v_$args = (v_$args[0] = 32, v_$args[2] = v_$args[1], v_$args[1] = v_$k, v_$args);
              continue;
            }
            case 25: {
              v_$args = (v_$args[0] = 33, v_$args[1] = v_t[3], v_$args[2] = [
                30,
                v_$k,
                v_t[1],
                v_t[2]
              ], v_$args);
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
                  const v_$do__e__6 = __s[1];
                  return [3, v_$do__e__6];
                }
                case 4: {
                  const v_m = __s[1];
                  v_times = v_m;
                  v_t = v_$scc$$apply$mirror__$cps$mirror([33, v_t, [29]]);
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$inl5$depth = 5000000 | 0;
  const v_runDemo = (() => {
    let v_$inl7$scrut;
    $join6: {
      const __s = v_buildLeft(v_$inl5$depth, [24]);
      switch (__s[0]) {
        case 3: {
          const v_$inl1$$do__e__3 = __s[1];
          return [3, v_$inl1$$do__e__3];
        }
        case 4: {
          const v_$inl2$l = __s[1];
          v_$inl7$scrut = (s => {
            switch (s[0]) {
              case 3: {
                const v_$inl3$$do__e__2 = s[1];
                return [3, v_$inl3$$do__e__2];
              }
              case 4: {
                const v_$inl4$r = s[1];
                return [4, [25, v_$inl2$l, 0 | 0, v_$inl4$r]];
              }
            }
          })(v_buildRight(v_$inl5$depth, [24]));
          break $join6;
        }
      }
    }
    switch (v_$inl7$scrut[0]) {
      case 3: {
        return v_$inl7$scrut;
      }
      case 4: {
        {
          const __s = v_mirrorN(25 | 0, v_$inl7$scrut[1]);
          switch (__s[0]) {
            case 3: {
              const v_$do__e__0 = __s[1];
              return [3, v_$do__e__0];
            }
            case 4: {
              const v_mirrored = __s[1];
              return [
                4,
                v_$scc$deepestLeftA__deepestLeftB__deepestLeftC(
                  [26, 0 | 0, v_mirrored]
                )
              ];
            }
          }
        }
      }
    }
  })();

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
