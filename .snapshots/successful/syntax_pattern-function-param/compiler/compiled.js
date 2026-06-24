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

  const v_triple = [16, 10 | 0, 20 | 0, 30 | 0];

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

  const v_pair = [15, 100 | 0, 200 | 0];

  const v_$inl14$$arg__0 = v_triple;
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$inl15$$do__e__3 = s[1];
        return [3, v_$inl15$$do__e__3];
      }
      case 4: {
        const v_$inl16$s0 = s[1];
        const v_$inl17$t = v_pair;
        return __concat(
          v_$inl16$s0,
          String(
            (s => {
              switch (s[0]) {
                case 3: {
                  return 0 | 0;
                }
                case 4: {
                  const v_$inl19$s = s[1];
                  return v_$inl19$s;
                }
              }
            })(__addInt32(v_$inl17$t[1], v_$inl17$t[2]))
          )
        );
      }
    }
  })(
    __concat(
      String(
        (s => {
          switch (s[0]) {
            case 3: {
              return 0 | 0;
            }
            case 4: {
              const v_$inl11$ab = s[1];
              {
                const __s = __addInt32(v_$inl11$ab, v_$inl14$$arg__0[3]);
                switch (__s[0]) {
                  case 3: {
                    return 0 | 0;
                  }
                  case 4: {
                    const v_$inl13$abc = __s[1];
                    return v_$inl13$abc;
                  }
                }
              }
            }
          }
        })(__addInt32(v_$inl14$$arg__0[1], v_$inl14$$arg__0[2]))
      ),
      " / "
    )
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 20: {
          return v_$x;
        }
        case 21: {
          const v_$pk__21 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__21;
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
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [21, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 22: {
          return v_$x;
        }
        case 23: {
          const v_$pk__23 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__23;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [23, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl22$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl22$x[1]];
          }
          case 4: {
            return [5, v_$inl22$x[1]];
          }
        }
      })(v_$inl22$x),
      [22]
    ),
    [20]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
