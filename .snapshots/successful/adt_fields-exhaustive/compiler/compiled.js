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

  const v_$apply$$df$andThenIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 26: {
          return v_$x;
        }
        case 27: {
          const v_$pk__27 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__27;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl2$p = [15, [25], [24]];
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 24: {
                    return "A?";
                  }
                  case 25: {
                    return "B?";
                  }
                }
              })(v_$inl2$p[1]),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [27, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl5$p = [15, [24], [25]];
  const main = v_$cps$$df$andThenIO$0(
    [
      7,
      (s => {
        switch (s[0]) {
          case 15: {
            const v_$inl4$____p1 = s[2];
            {
              const __s = v_$inl5$p[1];
              switch (__s[0]) {
                case 24: {
                  switch (v_$inl4$____p1[0]) {
                    case 24: {
                      return "AA";
                    }
                    case 25: {
                      return "AB";
                    }
                  }
                }
                case 25: {
                  switch (v_$inl4$____p1[0]) {
                    case 24: {
                      return "BA";
                    }
                    case 25: {
                      return "BB";
                    }
                  }
                }
              }
            }
          }
        }
      })(v_$inl5$p),
      [5, [0]]
    ],
    [26]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
