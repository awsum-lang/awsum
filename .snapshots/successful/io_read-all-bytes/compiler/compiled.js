"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __stdinReadAllBytes = () => {
    const buf = require("fs").readFileSync(0);
    let list = [13];
    for (let i = buf.length - 1; i >= 0; i--) {
      list = [14, buf[i], list];
    }
    return list;
  };

  const v_$apply$bytesToHexStringNoPrefix = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 28: {
          return v_$x;
        }
        case 29: {
          v_$x = (s => {
            switch (s[0]) {
              case 3: {
                return v_$x;
              }
              case 4: {
                return __concat(v_$k[2].toString(16).padStart(2, "0"), v_$x[1]);
              }
            }
          })(v_$x);
          v_$k = v_$k[1];
          continue;
        }
      }
    }
  };

  const v_$cps$bytesToHexStringNoPrefix = (v_bytes, v_$k) => {
    while (true) {
      switch (v_bytes[0]) {
        case 13: {
          return v_$apply$bytesToHexStringNoPrefix(v_$k, [4, ""]);
        }
        case 14: {
          const v_b = v_bytes[1];
          const v_rest = v_bytes[2];
          v_$k = [29, v_$k, v_b];
          v_bytes = v_rest;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$1 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$1 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$1(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$1(v_$k, [7, "TOO_LONG", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [31, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 10: {
          const v_cont = v_io[1];
          return v_$apply$$df$handleErrorIO$1(v_$k, [10, [20, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$9 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$9 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl5$x = v_$cps$bytesToHexStringNoPrefix(v_io[1], [28]);
          return v_$apply$$df$andThenIO$9(
            v_$k,
            (s => {
              switch (s[0]) {
                case 3: {
                  return [6, v_$inl5$x[1]];
                }
                case 4: {
                  return [5, v_$inl5$x[1]];
                }
              }
            })(v_$inl5$x)
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$9(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [35, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 10: {
          const v_cont = v_io[1];
          return v_$apply$$df$andThenIO$9(v_$k, [10, [21, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$5 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 32: {
          return v_$x;
        }
        case 33: {
          const v_$pk__33 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__33;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$5 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$5(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$5(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [33, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 10: {
          const v_cont = v_io[1];
          return v_$apply$$df$andThenIO$5(v_$k, [10, [22, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$scc$$apply1__$df$$lam$11$4__$df$$lam$2$12__$df$$lam$2$8 = (
    v_$k,
    v_$x
  ) => {
    while (true) {
      switch (v_$k[0]) {
        case 36: {
          return v_$x;
        }
        case 37: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$1(v_$x, [30]);
          continue;
        }
        case 38: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$andThenIO$9(v_$x, [34]);
          continue;
        }
        case 39: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$andThenIO$5(v_$x, [32]);
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$df$$lam$11$4__$df$$lam$2$12__$df$$lam$2$8 = (
    v_$args,
    v_$k
  ) => {
    while (true) {
      switch (v_$args[0]) {
        case 24: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 20: {
              v_$args = (v_$args[0] = 25, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 21: {
              v_$args = (v_$args[0] = 26, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 22: {
              v_$args = (v_$args[0] = 27, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 23: {
              return v_$apply$$scc$$apply1__$df$$lam$11$4__$df$$lam$2$12__$df$$lam$2$8(
                v_$k,
                [5, v_$arg0]
              );
            }
          }
        }
        case 25: {
          v_$args = (v_$args[0] = 24, v_$args);
          v_$k = [37, v_$k];
          continue;
        }
        case 26: {
          v_$args = (v_$args[0] = 24, v_$args);
          v_$k = [38, v_$k];
          continue;
        }
        case 27: {
          v_$args = (v_$args[0] = 24, v_$args);
          v_$k = [39, v_$k];
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
          const v_$inl8$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 10: {
          const __t0 = (() => {
            const v_$inl9$$arg0 = __stdinReadAllBytes();
            return v_$cps$$scc$$apply1__$df$$lam$11$4__$df$$lam$2$12__$df$$lam$2$8(
              [24, v_io[1], v_$inl9$$arg0],
              [36]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$1(
    v_$cps$$df$andThenIO$5(v_$cps$$df$andThenIO$9([10, [23]], [34]), [32]),
    [30]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
