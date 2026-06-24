"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const v_result = [4, String(115 | 0)];

  const v_$apply$$df$handleErrorIO$2 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 8: {
          return v_$x;
        }
        case 9: {
          const v_$pk__9 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__9;
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
          v_$k = [9, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$6 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 10: {
          return v_$x;
        }
        case 11: {
          const v_$pk__11 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__11;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$6 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$0$andThenIO$6(
            v_$k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$6(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [11, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl9$x = v_result;
  const main = v_$cps$$df$handleErrorIO$2(
    v_$cps$$df$$rowmono$0$andThenIO$6(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl9$x[1]];
          }
          case 4: {
            return [5, v_$inl9$x[1]];
          }
        }
      })(v_$inl9$x),
      [10]
    ),
    [8]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
