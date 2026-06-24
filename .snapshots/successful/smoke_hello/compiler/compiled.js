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

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 33: {
          return v_$x;
        }
        case 34: {
          const v_$pk__34 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__34;
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
          v_$k = [34, v_$k, v_s];
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

  const v_$apply$$df$$rowmono$1$andThenIO$8 = (v_$k, v_$x) => {
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

  const v_$cps$$df$$rowmono$1$andThenIO$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl35$args = v_io[1];
          const v_$inl32$x = (s => {
            switch (s[0]) {
              case 13: {
                return [3, [3864168810, [24]]];
              }
              case 14: {
                {
                  const __s = __concat("Hello, ", v_$inl35$args[1]);
                  switch (__s[0]) {
                    case 3: {
                      const v_$inl27$$do__e__0 = __s[1];
                      return [3, [589989748, v_$inl27$$do__e__0]];
                    }
                    case 4: {
                      const v_$inl28$hello = __s[1];
                      const v_$inl29$____input = __concat(v_$inl28$hello, "!");
                      switch (v_$inl29$____input[0]) {
                        case 3: {
                          return [3, [589989748, v_$inl29$____input[1]]];
                        }
                        case 4: {
                          return v_$inl29$____input;
                        }
                      }
                    }
                  }
                }
              }
            }
          })(v_$inl35$args);
          return v_$apply$$df$$rowmono$1$andThenIO$8(
            v_$k,
            (s => {
              switch (s[0]) {
                case 3: {
                  return [6, v_$inl32$x[1]];
                }
                case 4: {
                  return [5, v_$inl32$x[1]];
                }
              }
            })(v_$inl32$x)
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$1$andThenIO$8(v_$k, v_io);
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
          return v_$apply$$df$$rowmono$1$andThenIO$8(v_$k, [8, [26, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
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

  const v_$cps$$df$$rowmono$0$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(
            v_$k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, v_io);
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
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, [8, [25, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$scc$$apply1__$df$$lam$15$5__$df$$lam$18$9__$df$$lam$9$1 = (
    v_$k,
    v_$x
  ) => {
    while (true) {
      switch (v_$k[0]) {
        case 39: {
          return v_$x;
        }
        case 40: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$0$andThenIO$4(v_$x, [35]);
          continue;
        }
        case 41: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$1$andThenIO$8(v_$x, [37]);
          continue;
        }
        case 42: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$0(v_$x, [33]);
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$df$$lam$15$5__$df$$lam$18$9__$df$$lam$9$1 = (
    v_$args,
    v_$k
  ) => {
    while (true) {
      switch (v_$args[0]) {
        case 29: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 25: {
              v_$args = (v_$args[0] = 30, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 26: {
              v_$args = (v_$args[0] = 31, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 27: {
              v_$args = (v_$args[0] = 32, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 28: {
              return v_$apply$$scc$$apply1__$df$$lam$15$5__$df$$lam$18$9__$df$$lam$9$1(
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
          v_$k = [40, v_$k];
          continue;
        }
        case 31: {
          v_$args = (v_$args[0] = 29, v_$args);
          v_$k = [41, v_$k];
          continue;
        }
        case 32: {
          v_$args = (v_$args[0] = 29, v_$args);
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
          const v_$inl38$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl39$$arg0 = __getArgs();
            return v_$cps$$scc$$apply1__$df$$lam$15$5__$df$$lam$18$9__$df$$lam$9$1(
              [29, v_io[1], v_$inl39$$arg0],
              [39]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4(
      v_$cps$$df$$rowmono$1$andThenIO$8([8, [28]], [37]),
      [35]
    ),
    [33]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
