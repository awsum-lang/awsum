"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

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

  const v_label = v_k => {
    let v_$inl1$scrut;
    $join0: {
      const __s = __eqInt32(v_k, 7 | 0);
      switch (__s[0]) {
        case 1: {
          return "x";
        }
        case 2: {
          v_$inl1$scrut = (s => {
            switch (s[0]) {
              case 1: {
                return [24];
              }
              case 2: {
                {
                  const __s = __eqInt32(v_k, 1 | 0);
                  switch (__s[0]) {
                    case 1: {
                      return [25];
                    }
                    case 2: {
                      return [26];
                    }
                  }
                }
              }
            }
          })(__eqInt32(v_k, 0 | 0));
          break $join0;
        }
      }
    }
    switch (v_$inl1$scrut[0]) {
      case 24: {
        return "x";
      }
      case 25: {
        return "y";
      }
      case 26: {
        return "z";
      }
    }
  };

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
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
                  return [7, "UPS", [5, [0]]];
                }
                case 589989748: {
                  return [7, "STL", [5, [0]]];
                }
              }
            })(v_io[1])
          );
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
          return v_$apply$$df$handleErrorIO$0(v_$k, [8, [31, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 38: {
          return v_$x;
        }
        case 39: {
          const v_$pk__39 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__39;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl12$args = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$4(
            v_$k,
            (s => {
              switch (s[0]) {
                case 13: {
                  return [7, v_label(3 | 0), [5, [0]]];
                }
                case 14: {
                  {
                    const __s = __parseInt32(v_$inl12$args[1]);
                    switch (__s[0]) {
                      case 3: {
                        return [7, "PARSE", [5, [0]]];
                      }
                      case 4: {
                        const v_$inl11$n = __s[1];
                        return [7, v_label(v_$inl11$n), [5, [0]]];
                      }
                    }
                  }
                }
              }
            })(v_$inl12$args)
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [39, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, [8, [30, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 40: {
          return v_$x;
        }
        case 41: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$0$andThenIO$4(v_$x, [38]);
          continue;
        }
        case 42: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$0(v_$x, [36]);
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1 = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 33: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 30: {
              v_$args = (v_$args[0] = 34, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 31: {
              v_$args = (v_$args[0] = 35, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 32: {
              return v_$apply$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1(
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
        case 34: {
          v_$args = (v_$args[0] = 33, v_$args);
          v_$k = [41, v_$k];
          continue;
        }
        case 35: {
          v_$args = (v_$args[0] = 33, v_$args);
          v_$k = [42, v_$k];
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
          const v_$inl15$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl16$$arg0 = __getArgs();
            return v_$cps$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1(
              [33, v_io[1], v_$inl16$$arg0],
              [40]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4([8, [32]], [38]),
    [36]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
