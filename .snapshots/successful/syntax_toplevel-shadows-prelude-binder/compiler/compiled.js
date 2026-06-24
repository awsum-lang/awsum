"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

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

  const v_$apply$$lift$18 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 19: {
          return v_$x;
        }
        case 20: {
          const v_$pk__20 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__20;
          continue;
        }
      }
    }
  };

  const v_$cps$$lift$18 = (v_____input, v_$k) => {
    while (true) {
      switch (v_____input[0]) {
        case 5: {
          return v_$apply$$lift$18(v_$k, v_____input);
        }
        case 6: {
          const v_____f0 = v_____input[1];
          return v_$apply$$lift$18(v_$k, [6, [882564211, v_____f0]]);
        }
        case 7: {
          const v_____f0 = v_____input[1];
          const v_____f1 = v_____input[2];
          v_$k = [20, v_$k, v_____f0];
          v_____input = v_____f1;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 21: {
          return v_$x;
        }
        case 22: {
          const v_$pk__22 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__22;
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
                case 882564211: {
                  return [7, "OVERFLOW", [5, [0]]];
                }
                case 3768445577: {
                  return [7, "UNDERFLOW", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [22, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$1$andThenIO$8 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 25: {
          return v_$x;
        }
        case 26: {
          const v_$pk__26 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__26;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$1$andThenIO$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl6$x$u1 = __succInt32(v_io[1]);
          return v_$apply$$df$$rowmono$1$andThenIO$8(
            v_$k,
            v_$cps$$lift$18(
              (s => {
                switch (s[0]) {
                  case 3: {
                    return [6, v_$inl6$x$u1[1]];
                  }
                  case 4: {
                    return [5, v_$inl6$x$u1[1]];
                  }
                }
              })(v_$inl6$x$u1),
              [19]
            )
          );
        }
        case 6: {
          const v_e = v_io[1];
          return v_$apply$$df$$rowmono$1$andThenIO$8(
            v_$k,
            [6, [3768445577, v_e]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [26, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 23: {
          return v_$x;
        }
        case 24: {
          const v_$pk__24 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__24;
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
            [7, String(v_io[1]), [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [24, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl11$x$u1 = [4, 6 | 0];
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4(
      v_$cps$$df$$rowmono$1$andThenIO$8(
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v_$inl11$x$u1[1]];
            }
            case 4: {
              return [5, v_$inl11$x$u1[1]];
            }
          }
        })(v_$inl11$x$u1),
        [25]
      ),
      [23]
    ),
    [21]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
