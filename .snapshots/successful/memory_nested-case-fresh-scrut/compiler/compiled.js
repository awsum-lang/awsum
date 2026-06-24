"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const __parseInt32 = s => {
    if (!/^-?[0-9]+$/.test(s)) {
      return [3, [22]];
    }
    const n = Number(s);
    if (n < -2147483648 || n > 2147483647) {
      return [3, [22]];
    }
    return [4, n | 0];
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

  const v_dispatch = v_n => {
    {
      const __s = __eqInt32(v_n, 0 | 0);
      switch (__s[0]) {
        case 1: {
          return 0 | 0;
        }
        case 2: {
          {
            const __s = __eqInt32(v_n, 1 | 0);
            switch (__s[0]) {
              case 1: {
                return 10 | 0;
              }
              case 2: {
                {
                  const __s = __eqInt32(v_n, 2 | 0);
                  switch (__s[0]) {
                    case 1: {
                      return 20 | 0;
                    }
                    case 2: {
                      {
                        const __s = __eqInt32(v_n, 3 | 0);
                        switch (__s[0]) {
                          case 1: {
                            return 30 | 0;
                          }
                          case 2: {
                            {
                              const __s = __eqInt32(v_n, 4 | 0);
                              switch (__s[0]) {
                                case 1: {
                                  return 40 | 0;
                                }
                                case 2: {
                                  {
                                    const __s = __eqInt32(v_n, 5 | 0);
                                    switch (__s[0]) {
                                      case 1: {
                                        return 50 | 0;
                                      }
                                      case 2: {
                                        {
                                          const __s = __eqInt32(v_n, 6 | 0);
                                          switch (__s[0]) {
                                            case 1: {
                                              return 60 | 0;
                                            }
                                            case 2: {
                                              {
                                                const __s = __eqInt32(
                                                  v_n,
                                                  7 | 0
                                                );
                                                switch (__s[0]) {
                                                  case 1: {
                                                    return 70 | 0;
                                                  }
                                                  case 2: {
                                                    {
                                                      const __s = __eqInt32(
                                                        v_n,
                                                        8 | 0
                                                      );
                                                      switch (__s[0]) {
                                                        case 1: {
                                                          return 80 | 0;
                                                        }
                                                        case 2: {
                                                          {
                                                            const __s = __eqInt32(
                                                              v_n,
                                                              9 | 0
                                                            );
                                                            switch (__s[0]) {
                                                              case 1: {
                                                                return 90 | 0;
                                                              }
                                                              case 2: {
                                                                return 999 | 0;
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

  const v_$apply$$df$handleErrorIO$8 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$8(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$8(
            v_$k,
            (s => {
              switch (s[0]) {
                case 882564211: {
                  return [7, "OVERFLOW", [5, [0]]];
                }
                case 2448244154: {
                  return [7, "PARSE_ERROR", [5, [0]]];
                }
                case 3768445577: {
                  return [7, "UNDERFLOW", [5, [0]]];
                }
                case 3864168810: {
                  return [7, "NO_ARG", [5, [0]]];
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
          return v_$apply$$df$handleErrorIO$8(v_$k, [8, [28, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 35: {
          return v_$x;
        }
        case 36: {
          const v_$pk__36 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__36;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$0(
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
          v_$k = [36, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$handleErrorIO$0(v_$k, [8, [27, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$1$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 37: {
          return v_$x;
        }
        case 38: {
          const v_$pk__38 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__38;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$12 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 41: {
          return v_$x;
        }
        case 42: {
          const v_$pk__42 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__42;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$12 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$0$andThenIO$12(
            v_$k,
            [7, String(v_io[1]), [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$12(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [42, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$12(v_$k, [8, [25, v_cont]]);
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$1$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl23$args = v_io[1];
          const v_$inl20$res = (s => {
            switch (s[0]) {
              case 13: {
                return [3, [3864168810, [24]]];
              }
              case 14: {
                {
                  const __s = __parseInt32(v_$inl23$args[1]);
                  switch (__s[0]) {
                    case 3: {
                      const v_$inl18$$do__e__0 = __s[1];
                      return [3, [2448244154, v_$inl18$$do__e__0]];
                    }
                    case 4: {
                      const v_$inl19$n = __s[1];
                      return __addInt32(
                        v_dispatch(v_$inl19$n),
                        v_dispatch(v_$inl19$n)
                      );
                    }
                  }
                }
              }
            }
          })(v_$inl23$args);
          return v_$apply$$df$$rowmono$1$andThenIO$4(
            v_$k,
            v_$cps$$df$handleErrorIO$8(
              v_$cps$$df$$rowmono$0$andThenIO$12(
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [6, v_$inl20$res[1]];
                    }
                    case 4: {
                      return [5, v_$inl20$res[1]];
                    }
                  }
                })(v_$inl20$res),
                [41]
              ),
              [39]
            )
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$1$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [38, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$$rowmono$1$andThenIO$4(v_$k, [8, [26, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$scc$$apply1__$df$$lam$15$13__$df$$lam$18$5__$df$$lam$9$1__$df$$lam$9$9 = (
    v_$k,
    v_$x
  ) => {
    while (true) {
      switch (v_$k[0]) {
        case 43: {
          return v_$x;
        }
        case 44: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$0$andThenIO$12(v_$x, [41]);
          continue;
        }
        case 45: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$1$andThenIO$4(v_$x, [37]);
          continue;
        }
        case 46: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$0(v_$x, [35]);
          continue;
        }
        case 47: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$8(v_$x, [39]);
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$df$$lam$15$13__$df$$lam$18$5__$df$$lam$9$1__$df$$lam$9$9 = (
    v_$args,
    v_$k
  ) => {
    while (true) {
      switch (v_$args[0]) {
        case 30: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 25: {
              v_$args = (v_$args[0] = 31, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 26: {
              v_$args = (v_$args[0] = 32, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 27: {
              v_$args = (v_$args[0] = 33, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 28: {
              v_$args = (v_$args[0] = 34, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 29: {
              return v_$apply$$scc$$apply1__$df$$lam$15$13__$df$$lam$18$5__$df$$lam$9$1__$df$$lam$9$9(
                v_$k,
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [6, v_$arg0[1]];
                    }
                    case 4: {
                      return [5, v_$arg0[1]];
                    }
                  }
                })(v_$arg0)
              );
            }
          }
        }
        case 31: {
          v_$args = (v_$args[0] = 30, v_$args);
          v_$k = [44, v_$k];
          continue;
        }
        case 32: {
          v_$args = (v_$args[0] = 30, v_$args);
          v_$k = [45, v_$k];
          continue;
        }
        case 33: {
          v_$args = (v_$args[0] = 30, v_$args);
          v_$k = [46, v_$k];
          continue;
        }
        case 34: {
          v_$args = (v_$args[0] = 30, v_$args);
          v_$k = [47, v_$k];
          continue;
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
          const v_$inl26$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl27$$arg0 = __getArgs();
            return v_$cps$$scc$$apply1__$df$$lam$15$13__$df$$lam$18$5__$df$$lam$9$1__$df$$lam$9$9(
              [30, v_io[1], v_$inl27$$arg0],
              [43]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$1$andThenIO$4([8, [29]], [37]),
    [35]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
