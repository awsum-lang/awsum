"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __entryArgEither = arg => {
    if (arg.length > 134217728) {
      return [3, [589989748, [19]]];
    }
    for (let i = 0; i < arg.length; i++) {
      const c = arg.charCodeAt(i);
      if (c >= 0xD800 && c <= 0xDBFF) {
        if (i + 1 >= arg.length) {
          return [3, [502975519, [20]]];
        }
        const next = arg.charCodeAt(i + 1);
        if (next < 0xDC00 || next > 0xDFFF) {
          return [3, [502975519, [20]]];
        }
        i++;
      } else {
        if (c >= 0xDC00 && c <= 0xDFFF) {
          return [3, [502975519, [20]]];
        }
      }
    }
    return [4, arg];
  };

  const __getArgs = () => {
    const args = process.argv.slice(2);
    let list = [13];
    for (let i = args.length - 1; i >= 0; i--) {
      const v = __entryArgEither(args[i]);
      if (v[0] !== 4) {
        return v;
      }
      list = [14, v[1], list];
    }
    return [4, list];
  };

  const v_$apply$$df$handleErrorIO$2 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 40: {
          return v_$x;
        }
        case 41: {
          const v_$pk__41 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__41;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$2 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$2(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$2(
            v_$k,
            (s => {
              switch (s[0]) {
                case 502975519: {
                  return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
                }
                case 589989748: {
                  return [7, "STRING_TOO_LONG", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [41, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$handleErrorIO$2(v_$k, [8, [27, v_cont]]);
        }
      }
    }
  };

  const v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$$x$1714952523 = v_$args$1 => {
    while (true) {
      switch (v_$args$1[0]) {
        case 52: {
          const v_$k = v_$args$1[1];
          const v_$x = v_$args$1[2];
          switch (v_$k[0]) {
            case 42: {
              return v_$x;
            }
            case 43: {
              v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = [
                37,
                v_$x
              ], v_$args$1[2] = v_$k[1], v_$args$1);
              continue;
            }
            case 44: {
              v_$args$1 = (v_$args$1[0] = 52, v_$args$1[1] = v_$k[1], v_$args$1[2] = v_$cps$$df$handleErrorIO$2(
                v_$x,
                [40]
              ), v_$args$1);
              continue;
            }
            case 45: {
              v_$args$1 = (v_$args$1[0] = 52, v_$args$1[1] = v_$k[1], v_$args$1[2] = [
                24,
                v_$x
              ], v_$args$1);
              continue;
            }
            case 46: {
              v_$args$1 = (v_$args$1[0] = 52, v_$args$1[1] = v_$k[1], v_$args$1[2] = [
                24,
                v_$x
              ], v_$args$1);
              continue;
            }
            case 47: {
              v_$args$1 = [
                52,
                v_$k[1],
                (v_$args$1[0] = 25, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_$k[2], v_$args$1)
              ];
              continue;
            }
            case 48: {
              v_$args$1 = [
                52,
                v_$k[1],
                (v_$args$1[0] = 7, v_$args$1[1] = v_$k[2], v_$args$1)
              ];
              continue;
            }
            case 50: {
              v_$args$1 = [
                52,
                v_$k[1],
                (v_$args$1[0] = 15, v_$args$1[1] = v_$k[2], v_$args$1)
              ];
              continue;
            }
            case 49: {
              v_$args$1 = [
                53,
                (v_$args$1[0] = 32, v_$args$1[1] = v_$k[2], v_$args$1[2] = v_$k[3], v_$args$1),
                [50, v_$k[1], v_$x]
              ];
              continue;
            }
            case 51: {
              v_$args$1 = [
                52,
                v_$k[1],
                (v_$args$1[0] = 7, v_$args$1[1] = (s => {
                  switch (s[0]) {
                    case 24: {
                      {
                        const __s = v_$x[1];
                        switch (__s[0]) {
                          case 24: {
                            return "more-more";
                          }
                          case 25: {
                            return "more-done-tuple-bool";
                          }
                        }
                      }
                    }
                    case 25: {
                      return "done";
                    }
                  }
                })(v_$x), v_$args$1[2] = [5, [0]], v_$args$1)
              ];
              continue;
            }
          }
        }
        case 53: {
          const v_$args = v_$args$1[1];
          const v_$k = v_$args$1[2];
          switch (v_$args[0]) {
            case 32: {
              const v_$cl = v_$args[1];
              const v_$arg0 = v_$args[2];
              switch (v_$cl[0]) {
                case 26: {
                  v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = (v_$args[0] = 33, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
                case 27: {
                  v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = (v_$args[0] = 34, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
                case 28: {
                  v_$args$1 = (v_$args[0] = 52, v_$args[1] = v_$k, v_$args[2] = (s => {
                    switch (s[0]) {
                      case 3: {
                        return [6, v_$arg0[1]];
                      }
                      case 4: {
                        return [5, v_$arg0[1]];
                      }
                    }
                  })(v_$arg0), v_$args);
                  continue;
                }
                case 29: {
                  v_$args$1 = (v_$args[0] = 52, v_$args[1] = v_$k, v_$args[2] = [
                    796142685,
                    v_$arg0
                  ], v_$args);
                  continue;
                }
                case 30: {
                  v_$args$1 = (v_$args[0] = 53, v_$args[1] = [
                    38,
                    v_$cl[1],
                    v_$cl[2],
                    v_$arg0
                  ], v_$args[2] = v_$k, v_$args);
                  continue;
                }
                case 31: {
                  v_$args$1 = (v_$args[0] = 52, v_$args[1] = v_$k, v_$args);
                  continue;
                }
              }
            }
            case 33: {
              v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = (v_$args[0] = 32, v_$args), v_$args$1[2] = [
                43,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 34: {
              v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = (v_$args[0] = 32, v_$args), v_$args$1[2] = [
                44,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 35: {
              const v_$mapin = v_$args[1];
              switch (v_$mapin[0]) {
                case 24: {
                  const v_$mx$0 = v_$mapin[1];
                  v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = [
                    36,
                    v_$mx$0,
                    [29],
                    [31]
                  ], v_$args$1[2] = [45, v_$k], v_$args$1);
                  continue;
                }
                case 25: {
                  const v_$mx$0 = v_$mapin[1];
                  const v_$mx$1 = v_$mapin[2];
                  v_$args$1 = (v_$args$1[0] = 52, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = [
                    25,
                    [796142685, v_$mx$0],
                    v_$mx$1
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 36: {
              const v_$mapin = v_$args[1];
              const v_$df$$map$Tw$1$cap0$0 = v_$args[2];
              const v_$df$$map$Tw$1$cap0$1 = v_$args[3];
              switch (v_$mapin[0]) {
                case 24: {
                  const v_$mx$0 = v_$mapin[1];
                  v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = (v_$args[0] = 36, v_$args[1] = v_$mx$0, v_$args[2] = [
                    30,
                    v_$df$$map$Tw$1$cap0$0,
                    v_$df$$map$Tw$1$cap0$1
                  ], v_$args[3] = [31], v_$args), v_$args$1[2] = [
                    46,
                    v_$k
                  ], v_$args$1);
                  continue;
                }
                case 25: {
                  const v_$mx$0 = v_$mapin[1];
                  const v_$mx$1 = v_$mapin[2];
                  v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = (v_$args[0] = 38, v_$args[1] = v_$args[2], v_$args[2] = v_$args[3], v_$args[3] = v_$mx$0, v_$args), v_$args$1[2] = [
                    47,
                    v_$k,
                    v_$mx$1
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 37: {
              const v_io = v_$args[1];
              switch (v_io[0]) {
                case 5: {
                  v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = (v_$args[0] = 39, v_$args[1] = v_io[1], v_$args), v_$args$1);
                  continue;
                }
                case 6: {
                  v_$args$1 = (v_$args$1[0] = 52, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_io, v_$args$1);
                  continue;
                }
                case 7: {
                  v_$args$1 = [
                    53,
                    (v_$args[0] = 37, v_$args[1] = v_io[2], v_$args),
                    (v_$args$1[0] = 48, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_io[1], v_$args$1)
                  ];
                  continue;
                }
                case 8: {
                  v_$args$1 = (v_$args$1[0] = 52, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = [
                    8,
                    (v_$args[0] = 26, v_$args[1] = v_io[1], v_$args)
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 38: {
              const v_$mf$0 = v_$args[1];
              const v_$mapin = v_$args[3];
              switch (v_$mapin[0]) {
                case 15: {
                  const v_$mx$0 = v_$mapin[1];
                  const v_$mx$1 = v_$mapin[2];
                  v_$args$1 = (v_$args$1[0] = 53, v_$args$1[1] = [
                    32,
                    v_$mf$0,
                    v_$mx$0
                  ], v_$args$1[2] = (v_$args[0] = 49, v_$args[1] = v_$k, v_$args[3] = v_$mx$1, v_$args), v_$args$1);
                  continue;
                }
              }
            }
            case 39: {
              const v_args = v_$args[1];
              v_$args$1 = [
                53,
                [
                  35,
                  (s => {
                    switch (s[0]) {
                      case 13: {
                        return (v_$args$1[0] = 25, v_$args$1[1] = [
                          1
                        ], v_$args$1[2] = [2], v_$args$1);
                      }
                      case 14: {
                        return (v_$args[0] = 24, v_$args[1] = [
                          25,
                          [15, [1], [2]],
                          [2]
                        ], v_$args);
                      }
                    }
                  })(v_args)
                ],
                [51, v_$k]
              ];
              continue;
            }
          }
        }
      }
    }
  };

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v_$inl14$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl15$$arg0 = __getArgs();
            return v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$$x$1714952523(
              [53, [32, v_io[1], v_$inl15$$arg0], [42]]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$2(
    v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$$x$1714952523(
      [53, [37, [8, [28]]], [42]]
    ),
    [40]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
