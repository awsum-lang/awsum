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

  const v_good = [4, 42 | 0];

  const v_bad = [3, [24]];

  const v_$inl12$x = v_good;
  const v_$inl15$renamedGood = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [25]];
      }
      case 4: {
        return v_$inl12$x;
      }
    }
  })(v_$inl12$x);
  const v_$inl11$x = v_bad;
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        switch (v_$inl15$renamedGood[0]) {
          case 3: {
            return [4, "bad-Left bad-Left"];
          }
          case 4: {
            return __concat(
              "bad-Left good-Right ",
              String(v_$inl15$renamedGood[1])
            );
          }
        }
      }
      case 4: {
        return [4, "WAT"];
      }
    }
  })(
    (s => {
      switch (s[0]) {
        case 3: {
          return [3, [25]];
        }
        case 4: {
          return v_$inl11$x;
        }
      }
    })(v_$inl11$x)
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

  const v_$inl22$x = v_res;
  const main = v_$cps$$df$handleErrorIO$1(
    v_$cps$$df$andThenIO$5(
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
