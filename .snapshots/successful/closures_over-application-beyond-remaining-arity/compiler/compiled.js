"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v_$apply$$df$handleErrorIO$3 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 47: {
          return v_$x;
        }
        case 48: {
          const v_$pk__48 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__48;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$3 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$3(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$3(
            v_$k,
            (s => {
              switch (s[0]) {
                case 502975519: {
                  return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
                }
                case 589989748: {
                  return [7, "STRING_TOO_LONG", [5, [0]]];
                }
                case 2671988933: {
                  return [7, "MISSING_ARG", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [48, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$handleErrorIO$3(v_$k, [8, [28, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$7 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 49: {
          return v_$x;
        }
        case 50: {
          const v_$pk__50 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__50;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$7 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$0$andThenIO$7(
            v_$k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$7(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [50, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$7(v_$k, [8, [26, v_cont]]);
        }
      }
    }
  };

  const v_$scc$$apply$$scc$$apply1__$apply2__$apply3__$df$$la$x$1235868101 = v_$args$1 => {
    while (true) {
      switch (v_$args$1[0]) {
        case 66: {
          const v_$k = v_$args$1[1];
          const v_$x = v_$args$1[2];
          switch (v_$k[0]) {
            case 51: {
              return v_$x;
            }
            case 52: {
              v_$args$1 = [
                67,
                (v_$args$1[0] = 36, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_$k[2], v_$args$1),
                v_$k[1]
              ];
              continue;
            }
            case 53: {
              v_$args$1 = [
                67,
                (v_$args$1[0] = 36, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_$k[2], v_$args$1),
                v_$k[1]
              ];
              continue;
            }
            case 54: {
              v_$args$1 = [
                67,
                (v_$args$1[0] = 36, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_$k[2], v_$args$1),
                v_$k[1]
              ];
              continue;
            }
            case 55: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                37,
                v_$x,
                v_$k[2],
                v_$k[3]
              ], v_$args$1[2] = v_$k[1], v_$args$1);
              continue;
            }
            case 56: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                37,
                v_$x,
                v_$k[2],
                v_$k[3]
              ], v_$args$1[2] = v_$k[1], v_$args$1);
              continue;
            }
            case 57: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                37,
                v_$x,
                v_$k[2],
                v_$k[3]
              ], v_$args$1[2] = v_$k[1], v_$args$1);
              continue;
            }
            case 58: {
              v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$k[1], v_$args$1[2] = v_$cps$$df$$rowmono$0$andThenIO$7(
                v_$x,
                [49]
              ), v_$args$1);
              continue;
            }
            case 59: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                42,
                v_$x
              ], v_$args$1[2] = v_$k[1], v_$args$1);
              continue;
            }
            case 60: {
              v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$k[1], v_$args$1[2] = v_$cps$$df$handleErrorIO$3(
                v_$x,
                [47]
              ), v_$args$1);
              continue;
            }
            case 61: {
              v_$args$1 = [
                66,
                v_$k[1],
                (v_$args$1[0] = 7, v_$args$1[1] = v_$k[2], v_$args$1)
              ];
              continue;
            }
            case 62: {
              v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$k[1], v_$args$1[2] = (s => {
                switch (s[0]) {
                  case 3: {
                    return [6, v_$x[1]];
                  }
                  case 4: {
                    return [5, v_$x[1]];
                  }
                }
              })(v_$x), v_$args$1);
              continue;
            }
            case 65: {
              v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$k[1], v_$args$1[2] = (() => {
                const v_$inl7$____input = __concat(v_$k[2], v_$x);
                return (s => {
                  switch (s[0]) {
                    case 3: {
                      return [3, [589989748, v_$inl7$____input[1]]];
                    }
                    case 4: {
                      return v_$inl7$____input;
                    }
                  }
                })(v_$inl7$____input);
              })(), v_$args$1);
              continue;
            }
            case 64: {
              const v_$pk__64 = v_$k[1];
              {
                const __s = __concat(v_$k[3], v_$x);
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__1 = __s[1];
                    v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$pk__64, v_$args$1[2] = [
                      3,
                      [589989748, v_$do__e__1]
                    ], v_$args$1);
                    continue;
                  }
                  case 4: {
                    const v_second = __s[1];
                    {
                      const __s = __concat(v_second, "|");
                      switch (__s[0]) {
                        case 3: {
                          const v_$do__e__0 = __s[1];
                          v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$pk__64, v_$args$1[2] = [
                            3,
                            [589989748, v_$do__e__0]
                          ], v_$args$1);
                          continue;
                        }
                        case 4: {
                          const v_third = __s[1];
                          v_$args$1 = [
                            67,
                            (v_$args$1[0] = 44, v_$args$1[1] = [
                              24,
                              [35]
                            ], v_$args$1[2] = v_$k[2], v_$args$1),
                            [65, v_$pk__64, v_third]
                          ];
                          continue;
                        }
                      }
                    }
                  }
                }
              }
            }
            case 63: {
              const v_$pk__63 = v_$k[1];
              const v_arg = v_$k[2];
              {
                const __s = __concat(v_$x, "|");
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__2 = __s[1];
                    v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$pk__63, v_$args$1[2] = [
                      3,
                      [589989748, v_$do__e__2]
                    ], v_$args$1);
                    continue;
                  }
                  case 4: {
                    const v_first = __s[1];
                    v_$args$1 = [
                      67,
                      (v_$args$1[0] = 44, v_$args$1[1] = [
                        24,
                        [30, [34]]
                      ], v_$args$1[2] = v_arg, v_$args$1),
                      [64, v_$pk__63, v_arg, v_first]
                    ];
                    continue;
                  }
                }
              }
            }
          }
        }
        case 67: {
          const v_$args = v_$args$1[1];
          const v_$k = v_$args$1[2];
          switch (v_$args[0]) {
            case 36: {
              const v_$cl = v_$args[1];
              const v_$arg0 = v_$args[2];
              switch (v_$cl[0]) {
                case 26: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 39, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
                case 27: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 40, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
                case 28: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 41, v_$args[1] = v_$cl[1], v_$args), v_$args$1);
                  continue;
                }
                case 29: {
                  v_$args$1 = (v_$args[0] = 66, v_$args[1] = v_$k, v_$args[2] = [
                    34
                  ], v_$args);
                  continue;
                }
                case 30: {
                  v_$args$1 = (v_$args[0] = 66, v_$args[1] = v_$k, v_$args[2] = [
                    33,
                    v_$cl[1]
                  ], v_$args);
                  continue;
                }
                case 31: {
                  v_$args$1 = (v_$args[0] = 66, v_$args[1] = v_$k, v_$args[2] = [
                    34
                  ], v_$args);
                  continue;
                }
                case 32: {
                  v_$args$1 = (v_$args[0] = 66, v_$args[1] = v_$k, v_$args[2] = (s => {
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
                case 33: {
                  v_$args$1 = (v_$args[0] = 66, v_$args[1] = v_$k, v_$args[2] = v_$cl[1], v_$args);
                  continue;
                }
                case 34: {
                  v_$args$1 = (v_$args[0] = 66, v_$args[1] = v_$k, v_$args);
                  continue;
                }
                case 35: {
                  v_$args$1 = (v_$args[0] = 66, v_$args[1] = v_$k, v_$args[2] = [
                    31,
                    v_$arg0
                  ], v_$args);
                  continue;
                }
              }
            }
            case 37: {
              const v_$cl = v_$args[1];
              const v_$arg0 = v_$args[2];
              const v_$arg1 = v_$args[3];
              switch (v_$cl[0]) {
                case 26: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 39, v_$args$1[1] = v_$cl[1], v_$args$1[2] = v_$arg0, v_$args$1),
                    [52, v_$k, v_$arg1]
                  ];
                  continue;
                }
                case 27: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 40, v_$args$1[1] = v_$cl[1], v_$args$1[2] = v_$arg0, v_$args$1),
                    [53, v_$k, v_$arg1]
                  ];
                  continue;
                }
                case 28: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 41, v_$args$1[1] = v_$cl[1], v_$args$1[2] = v_$arg0, v_$args$1),
                    [54, v_$k, v_$arg1]
                  ];
                  continue;
                }
                case 29: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 36, v_$args$1[1] = [
                      34
                    ], v_$args$1[2] = v_$arg1, v_$args$1),
                    v_$k
                  ];
                  continue;
                }
                case 30: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 36, v_$args$1[1] = [
                      33,
                      v_$cl[1]
                    ], v_$args$1[2] = v_$arg1, v_$args$1),
                    v_$k
                  ];
                  continue;
                }
                case 31: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 36, v_$args$1[1] = [
                      34
                    ], v_$args$1[2] = v_$arg1, v_$args$1),
                    v_$k
                  ];
                  continue;
                }
                case 32: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 36, v_$args$1[1] = (s => {
                      switch (s[0]) {
                        case 3: {
                          return [6, v_$arg0[1]];
                        }
                        case 4: {
                          return [5, v_$arg0[1]];
                        }
                      }
                    })(v_$arg0), v_$args$1[2] = v_$arg1, v_$args$1),
                    v_$k
                  ];
                  continue;
                }
                case 33: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 36, v_$args$1[1] = v_$cl[1], v_$args$1[2] = v_$arg1, v_$args$1),
                    v_$k
                  ];
                  continue;
                }
                case 34: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 36, v_$args$1[1] = v_$arg0, v_$args$1[2] = v_$arg1, v_$args$1),
                    v_$k
                  ];
                  continue;
                }
                case 35: {
                  v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = [
                    34
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 38: {
              const v_$cl = v_$args[1];
              const v_$arg0 = v_$args[2];
              const v_$arg1 = v_$args[3];
              const v_$arg2 = v_$args[4];
              switch (v_$cl[0]) {
                case 26: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 39, v_$args$1[1] = v_$cl[1], v_$args$1[2] = v_$arg0, v_$args$1),
                    [55, v_$k, v_$arg1, v_$arg2]
                  ];
                  continue;
                }
                case 27: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 40, v_$args$1[1] = v_$cl[1], v_$args$1[2] = v_$arg0, v_$args$1),
                    [56, v_$k, v_$arg1, v_$arg2]
                  ];
                  continue;
                }
                case 28: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 41, v_$args$1[1] = v_$cl[1], v_$args$1[2] = v_$arg0, v_$args$1),
                    [57, v_$k, v_$arg1, v_$arg2]
                  ];
                  continue;
                }
                case 29: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                    37,
                    [34],
                    v_$arg1,
                    v_$arg2
                  ], v_$args$1);
                  continue;
                }
                case 30: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                    37,
                    [33, v_$cl[1]],
                    v_$arg1,
                    v_$arg2
                  ], v_$args$1);
                  continue;
                }
                case 31: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                    37,
                    [34],
                    v_$arg1,
                    v_$arg2
                  ], v_$args$1);
                  continue;
                }
                case 32: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                    37,
                    (s => {
                      switch (s[0]) {
                        case 3: {
                          return [6, v_$arg0[1]];
                        }
                        case 4: {
                          return [5, v_$arg0[1]];
                        }
                      }
                    })(v_$arg0),
                    v_$arg1,
                    v_$arg2
                  ], v_$args$1);
                  continue;
                }
                case 33: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                    37,
                    v_$cl[1],
                    v_$arg1,
                    v_$arg2
                  ], v_$args$1);
                  continue;
                }
                case 34: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = [
                    37,
                    v_$arg0,
                    v_$arg1,
                    v_$arg2
                  ], v_$args$1);
                  continue;
                }
                case 35: {
                  v_$args$1 = [
                    67,
                    (v_$args$1[0] = 36, v_$args$1[1] = [
                      34
                    ], v_$args$1[2] = v_$arg2, v_$args$1),
                    v_$k
                  ];
                  continue;
                }
              }
            }
            case 39: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 36, v_$args), v_$args$1[2] = [
                58,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 40: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 36, v_$args), v_$args$1[2] = [
                59,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 41: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 36, v_$args), v_$args$1[2] = [
                60,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 42: {
              const v_io = v_$args[1];
              switch (v_io[0]) {
                case 5: {
                  v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 43, v_$args[1] = v_io[1], v_$args), v_$args$1);
                  continue;
                }
                case 6: {
                  v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_io, v_$args$1);
                  continue;
                }
                case 7: {
                  v_$args$1 = [
                    67,
                    (v_$args[0] = 42, v_$args[1] = v_io[2], v_$args),
                    (v_$args$1[0] = 61, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = v_io[1], v_$args$1)
                  ];
                  continue;
                }
                case 8: {
                  v_$args$1 = (v_$args$1[0] = 66, v_$args$1[1] = v_$args$1[2], v_$args$1[2] = [
                    8,
                    (v_$args[0] = 27, v_$args[1] = v_io[1], v_$args)
                  ], v_$args$1);
                  continue;
                }
              }
            }
            case 43: {
              v_$args$1 = (v_$args$1[0] = 67, v_$args$1[1] = (v_$args[0] = 46, v_$args), v_$args$1[2] = [
                62,
                v_$k
              ], v_$args$1);
              continue;
            }
            case 44: {
              const v_b = v_$args[1];
              const v_arg = v_$args[2];
              v_$args$1 = (v_$args[0] = 67, v_$args[1] = [
                38,
                v_b[1],
                v_arg,
                v_arg,
                v_arg
              ], v_$args[2] = v_$k, v_$args);
              continue;
            }
            case 45: {
              const v_b = v_$args[1];
              const v_arg = v_$args[2];
              v_$args$1 = (v_$args[0] = 67, v_$args[1] = [
                37,
                v_b[1],
                v_arg,
                v_arg
              ], v_$args[2] = v_$k, v_$args);
              continue;
            }
            case 46: {
              const v_args = v_$args[1];
              let v_$inl18$scrut;
              $join17: {
                switch (v_args[0]) {
                  case 13: {
                    v_$args$1 = [66, v_$k, [3, [2671988933, [25]]]];
                    continue;
                  }
                  case 14: {
                    v_$inl18$scrut = [4, v_args[1]];
                    break $join17;
                  }
                }
              }
              switch (v_$inl18$scrut[0]) {
                case 3: {
                  v_$args$1 = [66, v_$k, [3, [2671988933, v_$inl18$scrut[1]]]];
                  continue;
                }
                case 4: {
                  const v_arg = v_$inl18$scrut[1];
                  v_$args$1 = [67, [45, [24, [29]], v_arg], [63, v_$k, v_arg]];
                  continue;
                }
              }
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
          const v_$inl19$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl20$$arg0 = __getArgs();
            return v_$scc$$apply$$scc$$apply1__$apply2__$apply3__$df$$la$x$1235868101(
              [67, [36, v_io[1], v_$inl20$$arg0], [51]]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$3(
    v_$cps$$df$$rowmono$0$andThenIO$7(
      v_$scc$$apply$$scc$$apply1__$apply2__$apply3__$df$$la$x$1235868101(
        [67, [42, [8, [32]]], [51]]
      ),
      [49]
    ),
    [47]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
