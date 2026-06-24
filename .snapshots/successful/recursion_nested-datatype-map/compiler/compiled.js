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
        case 39: {
          return v_$x;
        }
        case 40: {
          const v_$pk__40 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__40;
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
          v_$k = [40, v_$k, v_s];
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

  const v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2 = v_$args$1 => {
    while (true) {
      switch (v_$args$1[0]) {
        case 50: {
          const v_$k = v_$args$1[1];
          const v_$x = v_$args$1[2];
          switch (v_$k[0]) {
            case 41: {
              return v_$x;
            }
            case 42: {
              v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = [
                34,
                v_$x
              ], v_$args$1[2] = v_$k[1], v_$args$1);
              continue;
            }
            case 43: {
              v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$k[1], v_$args$1[2] = v_$cps$$df$handleErrorIO$2(
                v_$x,
                [39]
              ), v_$args$1);
              continue;
            }
            case 44: {
              v_$args$1 = [
                50,
                v_$k[1],
                (v_$args$1[0] = 7, v_$args$1[1] = v_$k[2], v_$args$1)
              ];
              continue;
            }
            case 45: {
              v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$k[1], v_$args$1[2] = [
                24,
                v_$x
              ], v_$args$1);
              continue;
            }
            case 46: {
              v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$k[1], v_$args$1[2] = [
                25,
                v_$x
              ], v_$args$1);
              continue;
            }
            case 47: {
              v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$k[1], v_$args$1[2] = [
                24,
                v_$x
              ], v_$args$1);
              continue;
            }
            case 48: {
              v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$k[1], v_$args$1[2] = [
                12,
                v_$x
              ], v_$args$1);
              continue;
            }
            case 49: {
              v_$args$1 = [
                50,
                v_$k[1],
                (v_$args$1[0] = 7, v_$args$1[1] = (s => {
                  switch (s[0]) {
                    case 24: {
                      const v_$inl4$inner = s[1];
                      switch (v_$inl4$inner[0]) {
                        case 24: {
                          return "deeper-deeper";
                        }
                        case 25: {
                          {
                            const __s = v_$inl4$inner[1];
                            switch (__s[0]) {
                              case 11: {
                                return "deeper-base-nothing";
                              }
                              case 12: {
                                return "deeper-base-just-bool";
                              }
                            }
                          }
                        }
                      }
                    }
                    case 25: {
                      return "base-bool";
                    }
                  }
                })(v_$x), v_$args$1[2] = [5, [0]], v_$args$1)
              ];
              continue;
            }
          }
        }
        case 51: {
          const v_$args = v_$args$1[1];
          const v_$k = v_$args$1[2];
          switch (v_$args[0]) {
            case 31: {
              const v_$cl = v_$args[1];
              const v_$arg0 = v_$args[2];
              switch (v_$cl[0]) {
                case 26: {
                  v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 32, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
                case 27: {
                  v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 33, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
                case 28: {
                  v_$args$1 = (v_$args[0] = 50, v_$args[1] = v_$k, v_$args[2] = (s => {
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
                  v_$args$1 = (v_$args[0] = 50, v_$args[1] = v_$k, v_$args[2] = [
                    796142685,
                    v_$arg0
                  ], v_$args);
                  continue;
                }
                case 30: {
                  v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 37, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
              }
            }
            case 32: {
              v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 31, v_$args), v_$args$1[2] = [
                42,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 33: {
              v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 31, v_$args), v_$args$1[2] = [
                43,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 34: {
              const v_io = v_$args[1];
              switch (v_io[0]) {
                case 5: {
                  v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 38, v_$args[1] = v_io[1], v_$args), v_$args$1);
                  continue;
                }
                case 6: {
                  v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_io, v_$args$1);
                  continue;
                }
                case 7: {
                  v_$args$1 = [
                    51,
                    (v_$args[0] = 34, v_$args[1] = v_io[2], v_$args),
                    (v_$args$1[0] = 44, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_io[1], v_$args$1)
                  ];
                  continue;
                }
                case 8: {
                  v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = [
                    8,
                    (v_$args[0] = 26, v_$args[1] = v_io[1], v_$args)
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 35: {
              const v_n = v_$args[1];
              const v_$df$mapNest$0$cap0$0 = v_$args[2];
              switch (v_n[0]) {
                case 24: {
                  const v_inner = v_n[1];
                  v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 35, v_$args[1] = v_inner, v_$args[2] = [
                    30,
                    v_$df$mapNest$0$cap0$0
                  ], v_$args), v_$args$1[2] = [45, v_$k], v_$args$1);
                  continue;
                }
                case 25: {
                  const v_a = v_n[1];
                  v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 37, v_$args[1] = v_$args[2], v_$args[2] = v_a, v_$args), v_$args$1[2] = [
                    46,
                    v_$k
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 36: {
              const v_n = v_$args[1];
              switch (v_n[0]) {
                case 24: {
                  const v_inner = v_n[1];
                  v_$args$1 = [
                    51,
                    (v_$args$1[0] = 35, v_$args$1[1] = v_inner, v_$args$1[2] = [
                      29
                    ], v_$args$1),
                    [47, v_$k]
                  ];
                  continue;
                }
                case 25: {
                  const v_a = v_n[1];
                  v_$args$1 = (v_$args$1[0] = 50, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = [
                    25,
                    [796142685, v_a]
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 37: {
              const v_m = v_$args[2];
              switch (v_m[0]) {
                case 11: {
                  v_$args$1 = (v_$args[0] = 50, v_$args[1] = v_$k, v_$args);
                  continue;
                }
                case 12: {
                  v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = (v_$args[0] = 31, v_$args[2] = v_m[1], v_$args), v_$args$1[2] = [
                    48,
                    v_$k
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 38: {
              const v_args = v_$args[1];
              v_$args$1 = (v_$args$1[0] = 51, v_$args$1[1] = [
                36,
                (s => {
                  switch (s[0]) {
                    case 13: {
                      return (v_$args[0] = 25, v_$args[1] = [1], v_$args);
                    }
                    case 14: {
                      return [
                        24,
                        [25, (v_$args[0] = 12, v_$args[1] = [1], v_$args)]
                      ];
                    }
                  }
                })(v_args)
              ], v_$args$1[2] = [49, v_$k], v_$args$1);
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
          const v_$inl13$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl14$$arg0 = __getArgs();
            return v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2(
              [51, [31, v_io[1], v_$inl14$$arg0], [41]]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$2(
    v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2(
      [51, [34, [8, [28]]], [41]]
    ),
    [39]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
