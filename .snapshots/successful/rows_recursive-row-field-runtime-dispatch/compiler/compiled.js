"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

  const __eqString = (a, b) => a === b ? [1] : [2];

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

  const v_$apply$walk = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 32: {
          return v_$x;
        }
        case 33: {
          const v_$pk__33 = v_$k[1];
          {
            const __s = __succInt32(v_$x);
            switch (__s[0]) {
              case 3: {
                v_$k = v_$pk__33;
                v_$x = 0 | 0;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                v_$k = v_$pk__33;
                v_$x = v_r;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v_$cps$walk = (v_c, v_$k) => {
    while (true) {
      switch (v_c[0]) {
        case 24: {
          return v_$apply$walk(v_$k, 0 | 0);
        }
        case 25: {
          const v_x = v_c[1];
          switch (v_x[0]) {
            case 2108399875: {
              v_$k = [33, v_$k];
              v_c = v_x[1];
              continue;
            }
            case 2711245919: {
              return v_$apply$walk(v_$k, v_x[1]);
            }
          }
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 34: {
          return v_$x;
        }
        case 35: {
          const v_$pk__35 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__35;
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
          v_$k = [35, v_$k, v_s];
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

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 36: {
          return v_$x;
        }
        case 37: {
          const v_$pk__37 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__37;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl17$args = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$4(
            v_$k,
            [
              7,
              String(
                v_$cps$walk(
                  (() => {
                    let v_$inl13$scrut;
                    $join12: {
                      switch (v_$inl17$args[0]) {
                        case 13: {
                          return [24];
                        }
                        case 14: {
                          v_$inl13$scrut = [12, v_$inl17$args[1]];
                          break $join12;
                        }
                      }
                    }
                    switch (v_$inl13$scrut[0]) {
                      case 11: {
                        return [24];
                      }
                      case 12: {
                        const v_$inl14$s = v_$inl13$scrut[1];
                        {
                          const __s = __eqString(v_$inl14$s, "int");
                          switch (__s[0]) {
                            case 1: {
                              return [25, [2711245919, 5 | 0]];
                            }
                            case 2: {
                              {
                                const __s = __eqString(v_$inl14$s, "deep");
                                switch (__s[0]) {
                                  case 1: {
                                    return [
                                      25,
                                      [2108399875, [25, [2108399875, [24]]]]
                                    ];
                                  }
                                  case 2: {
                                    return [24];
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  })(),
                  [32]
                )
              ),
              [5, [0]]
            ]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [37, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, [8, [26, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 38: {
          return v_$x;
        }
        case 39: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$0$andThenIO$4(v_$x, [36]);
          continue;
        }
        case 40: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$0(v_$x, [34]);
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1 = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 29: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 26: {
              v_$args = (v_$args[0] = 30, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 27: {
              v_$args = (v_$args[0] = 31, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 28: {
              return v_$apply$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1(
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
        case 30: {
          v_$args = (v_$args[0] = 29, v_$args);
          v_$k = [39, v_$k];
          continue;
        }
        case 31: {
          v_$args = (v_$args[0] = 29, v_$args);
          v_$k = [40, v_$k];
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
          const v_$inl20$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl21$$arg0 = __getArgs();
            return v_$cps$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1(
              [29, v_io[1], v_$inl21$$arg0],
              [38]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4([8, [28]], [36]),
    [34]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
