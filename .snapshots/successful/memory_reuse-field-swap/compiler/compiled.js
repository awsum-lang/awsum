"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_spin = (v_n, v_p) => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_p;
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  return v_p;
                }
                case 4: {
                  const v_m = __s[1];
                  switch (v_p[0]) {
                    case 24: {
                      const v_a = v_p[1];
                      const v_b = v_p[2];
                      v_n = v_m;
                      v_p = [24, v_b, v_a];
                      continue;
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

  const v_$cps$$df$andThenIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl4$q = v_spin(2 | 0, [24, String(7 | 0), "x"]);
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 3: {
                    return "L";
                  }
                  case 4: {
                    const v_$inl6$z = s[1];
                    return v_$inl6$z;
                  }
                }
              })(__concat(v_$inl4$q[1], v_$inl4$q[2])),
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

  const v_$inl9$q = v_spin(1 | 0, [24, String(7 | 0), "x"]);
  const main = v_$cps$$df$andThenIO$0(
    [
      7,
      (s => {
        switch (s[0]) {
          case 3: {
            return "L";
          }
          case 4: {
            const v_$inl8$z = s[1];
            return v_$inl8$z;
          }
        }
      })(__concat(v_$inl9$q[1], v_$inl9$q[2])),
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
