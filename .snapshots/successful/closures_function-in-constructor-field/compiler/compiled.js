"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v_callBox = (v_b, v_x) => {
    {
      const __s = v_b[1];
      switch (__s[0]) {
        case 25: {
          return __addInt32(v_x, v_x);
        }
        case 26: {
          {
            const __s = __addInt32(v_x, v_x);
            switch (__s[0]) {
              case 3: {
                const v_$inl3$$do__e__0 = __s[1];
                return [3, v_$inl3$$do__e__0];
              }
              case 4: {
                const v_$inl4$m = __s[1];
                return __addInt32(v_$inl4$m, v_x);
              }
            }
          }
        }
      }
    }
  };

  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__3 = s[1];
        return [3, v_$do__e__3];
      }
      case 4: {
        const v_d = s[1];
        {
          const __s = v_callBox([24, [26]], 7 | 0);
          switch (__s[0]) {
            case 3: {
              const v_$do__e__2 = __s[1];
              return [3, v_$do__e__2];
            }
            case 4: {
              const v_t = __s[1];
              {
                const __s = __concat(String(v_d), " ");
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__1 = __s[1];
                    return [3, [589989748, v_$do__e__1]];
                  }
                  case 4: {
                    const v_ds = __s[1];
                    const v_$inl7$____input = __concat(v_ds, String(v_t));
                    switch (v_$inl7$____input[0]) {
                      case 3: {
                        return [3, [589989748, v_$inl7$____input[1]]];
                      }
                      case 4: {
                        return v_$inl7$____input;
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
  })(v_callBox([24, [25]], 7 | 0));

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 27: {
          return v_$x;
        }
        case 28: {
          const v_$pk__28 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__28;
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
          v_$k = [28, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 29: {
          return v_$x;
        }
        case 30: {
          const v_$pk__30 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__30;
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
          v_$k = [30, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl13$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl13$x[1]];
          }
          case 4: {
            return [5, v_$inl13$x[1]];
          }
        }
      })(v_$inl13$x),
      [29]
    ),
    [27]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
