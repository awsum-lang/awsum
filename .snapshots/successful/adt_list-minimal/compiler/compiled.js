"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
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

  const v_$apply$$scc$show__showCons = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 26: {
          return v_$x;
        }
        case 27: {
          const v_$pk__27 = v_$k[1];
          switch (v_$x[0]) {
            case 3: {
              v_$k = v_$pk__27;
              continue;
            }
            case 4: {
              v_$x = __concat(v_$k[2], v_$x[1]);
              v_$k = v_$pk__27;
              continue;
            }
          }
        }
      }
    }
  };

  const v_$cps$$scc$show__showCons = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 20: {
          const v_xs = v_$args[1];
          switch (v_xs[0]) {
            case 13: {
              return v_$apply$$scc$show__showCons(v_$k, [4, ""]);
            }
            case 14: {
              const v_h = v_xs[1];
              const v_t = v_xs[2];
              v_$args = [21, v_h, v_t];
              continue;
            }
          }
        }
        case 21: {
          const v_h = v_$args[1];
          const v_t = v_$args[2];
          {
            const __s = __concat(v_h, ",");
            switch (__s[0]) {
              case 3: {
                const v_$do__e__1 = __s[1];
                return v_$apply$$scc$show__showCons(v_$k, [3, v_$do__e__1]);
              }
              case 4: {
                const v_hc = __s[1];
                v_$k = (v_$args[0] = 27, v_$args[1] = v_$k, v_$args[2] = v_hc, v_$args);
                v_$args = [20, v_t];
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v_res = v_$cps$$scc$show__showCons(
    [20, [14, "a", [14, "b", [14, "c", [13]]]]],
    [26]
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
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
          v_$k = [23, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 24: {
          return v_$x;
        }
        case 25: {
          const v_$pk__25 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__25;
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
          v_$k = [25, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl3$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl3$x[1]];
          }
          case 4: {
            return [5, v_$inl3$x[1]];
          }
        }
      })(v_$inl3$x),
      [24]
    ),
    [22]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
