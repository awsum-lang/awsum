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

  const v_inc42 = 42 | 0;

  const v_g = [4, 1 | 0];

  const v_$inl5$r = v_g;
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__3 = s[1];
        return [3, v_$do__e__3];
      }
      case 4: {
        const v_d = s[1];
        {
          const __s = __concat(String(v_inc42), " / ");
          switch (__s[0]) {
            case 3: {
              const v_$do__e__2 = __s[1];
              return [3, v_$do__e__2];
            }
            case 4: {
              const v_s0 = __s[1];
              return __concat(v_s0, v_d);
            }
          }
        }
      }
    }
  })(
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v_$inl5$r[1];
            switch (__s[0]) {
              case 2252990199: {
                return [4, "ErrA"];
              }
              case 2269767818: {
                return [4, "ErrB"];
              }
            }
          }
        }
        case 4: {
          return __concat("Ok ", String(v_$inl5$r[1]));
        }
      }
    })(v_$inl5$r)
  );

  const v_$apply$$df$handleErrorIO$1 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$1 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$1(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$1(
            v_$k,
            [7, "STRING_TOO_LONG", [5, [0]]]
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

  const v_$apply$$df$andThenIO$5 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 28: {
          return v_$x;
        }
        case 29: {
          const v_$pk__29 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__29;
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
          v_$k = [29, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl8$x = v_res;
  const main = v_$cps$$df$handleErrorIO$1(
    v_$cps$$df$andThenIO$5(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl8$x[1]];
          }
          case 4: {
            return [5, v_$inl8$x[1]];
          }
        }
      })(v_$inl8$x),
      [28]
    ),
    [26]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
