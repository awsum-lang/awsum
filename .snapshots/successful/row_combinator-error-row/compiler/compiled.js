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

  const v_c2 = [3, [332136403, [24]]];

  const v_c1 = [3, [332136403, [24]]];

  const v_$apply$$df$andThenIO$2 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$2 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl21$x = v_c2;
          return v_$apply$$df$andThenIO$2(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 3: {
                    {
                      const __s = v_$inl21$x[1];
                      switch (__s[0]) {
                        case 332136403: {
                          return "A";
                        }
                      }
                    }
                  }
                  case 4: {
                    return String(v_$inl21$x[1]);
                  }
                }
              })(v_$inl21$x),
              [5, [0]]
            ]
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

  const v_$inl30$x = v_c1;
  const main = v_$cps$$df$andThenIO$2(
    [
      7,
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v_$inl30$x[1];
              switch (__s[0]) {
                case 332136403: {
                  return "A";
                }
              }
            }
          }
          case 4: {
            return String(v_$inl30$x[1]);
          }
        }
      })(v_$inl30$x),
      [5, [0]]
    ],
    [25]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
