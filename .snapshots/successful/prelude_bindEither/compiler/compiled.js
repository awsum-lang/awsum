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

  const v_opA = [4, 1 | 0];

  const v_$inl9$x = v_opA;
  const v_$inl14$chained = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v_$inl9$x[1]]];
      }
      case 4: {
        const v_$inl6$____input = [4, v_$inl9$x[1]];
        switch (v_$inl6$____input[0]) {
          case 3: {
            return [3, [2269767818, v_$inl6$____input[1]]];
          }
          case 4: {
            return v_$inl6$____input;
          }
        }
      }
    }
  })(v_$inl9$x);
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        {
          const __s = v_$inl14$chained[1];
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
        return __concat("Ok ", String(v_$inl14$chained[1]));
      }
    }
  })(v_$inl14$chained);

  const v_$apply$$df$handleErrorIO$1 = (v_$k, v_$x) => {
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
          v_$k = [21, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$5 = (v_$k, v_$x) => {
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
          v_$k = [23, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl17$x = v_res;
  const main = v_$cps$$df$handleErrorIO$1(
    v_$cps$$df$andThenIO$5(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl17$x[1]];
          }
          case 4: {
            return [5, v_$inl17$x[1]];
          }
        }
      })(v_$inl17$x),
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
