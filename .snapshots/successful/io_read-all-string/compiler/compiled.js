"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __stdinReadAll = () => {
    let s;
    try {
      s = new TextDecoder("utf-8", {fatal: true, ignoreBOM: true}).decode(
        require("fs").readFileSync(0)
      );
    } catch (e) {
      return [3, [3239958583, [21]]];
    }
    if (s.length > 134217728) {
      return [3, [589989748, [19]]];
    }
    return [4, s];
  };

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 28: {
          return v_$x;
        }
        case 29: {
          const v_$pk__29 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__29;
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
                case 589989748: {
                  return [7, "STRING_TOO_LONG", [5, [0]]];
                }
                case 3239958583: {
                  return [7, "INVALID_UTF8", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [29, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 9: {
          const v_cont = v_io[1];
          return v_$apply$$df$handleErrorIO$0(v_$k, [9, [22, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 30: {
          return v_$x;
        }
        case 31: {
          const v_$pk__31 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__31;
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
          v_$k = [31, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 9: {
          const v_cont = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, [9, [23, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$scc$$apply1__$df$$lam$10$2__$df$$lam$14$6 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 32: {
          return v_$x;
        }
        case 33: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$0(v_$x, [28]);
          continue;
        }
        case 34: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$0$andThenIO$4(v_$x, [30]);
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$df$$lam$10$2__$df$$lam$14$6 = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 25: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 22: {
              v_$args = (v_$args[0] = 26, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 23: {
              v_$args = (v_$args[0] = 27, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 24: {
              return v_$apply$$scc$$apply1__$df$$lam$10$2__$df$$lam$14$6(
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
        case 26: {
          v_$args = (v_$args[0] = 25, v_$args);
          v_$k = [33, v_$k];
          continue;
        }
        case 27: {
          v_$args = (v_$args[0] = 25, v_$args);
          v_$k = [34, v_$k];
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
          const v_$inl4$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 9: {
          const __t0 = (() => {
            const v_$inl5$$arg0 = __stdinReadAll();
            return v_$cps$$scc$$apply1__$df$$lam$10$2__$df$$lam$14$6(
              [25, v_io[1], v_$inl5$$arg0],
              [32]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4([9, [24]], [30]),
    [28]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
