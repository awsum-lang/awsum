"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

  const __lengthUtf8Bytes = s => new TextEncoder().encode(s).length >>> 0;

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

  const v_describe = v_n => {
    {
      const __s = __eqUInt32(v_n, 0 >>> 0);
      switch (__s[0]) {
        case 1: {
          return "zero";
        }
        case 2: {
          {
            const __s = __eqUInt32(v_n, 1 >>> 0);
            switch (__s[0]) {
              case 1: {
                return "one";
              }
              case 2: {
                {
                  const __s = __eqUInt32(v_n, 2 >>> 0);
                  switch (__s[0]) {
                    case 1: {
                      return "two";
                    }
                    case 2: {
                      {
                        const __s = __eqUInt32(v_n, 11 >>> 0);
                        switch (__s[0]) {
                          case 1: {
                            return "eleven";
                          }
                          case 2: {
                            return String(v_n);
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

  const v_$apply$$df$andThenIO$0 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [7, v_describe(__lengthUtf8Bytes("ab")), [5, [0]]]
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

  const main = v_$cps$$df$andThenIO$0(
    [7, v_describe(__lengthUtf8Bytes(String(-2000000000 | 0))), [5, [0]]],
    [8]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
