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

  const v_$apply$$df$andThenIO$8 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 12: {
          return v_$x;
        }
        case 13: {
          const v_$pk__13 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__13;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl6$x = [2711245919, 9 | 0];
          return v_$apply$$df$andThenIO$8(
            v_$k,
            [7, String(v_$inl6$x[1]), [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [13, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 10: {
          return v_$x;
        }
        case 11: {
          const v_$pk__11 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__11;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl7$x = [3538687084, 11 >>> 0];
          return v_$apply$$df$andThenIO$4(
            v_$k,
            [7, String(v_$inl7$x[1]), [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [11, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$16 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 16: {
          return v_$x;
        }
        case 17: {
          const v_$pk__17 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__17;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$16 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl8$x = [2711245919, 9 | 0];
          return v_$apply$$df$andThenIO$16(
            v_$k,
            [7, String(v_$inl8$x[1]), [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [17, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$12 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 14: {
          return v_$x;
        }
        case 15: {
          const v_$pk__15 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__15;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$12 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl9$x = [2711245919, 7 | 0];
          return v_$apply$$df$andThenIO$12(
            v_$k,
            [7, String(v_$inl9$x[1]), [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [15, v_$k, v_s];
          v_io = v_next;
          continue;
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
          const v_$inl10$x = [3538687084, 13 >>> 0];
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [7, String(v_$inl10$x[1]), [5, [0]]]
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

  const v_$inl11$x = [2711245919, 7 | 0];
  const main = v_$cps$$df$andThenIO$0(
    v_$cps$$df$andThenIO$4(
      v_$cps$$df$andThenIO$8(
        v_$cps$$df$andThenIO$12(
          v_$cps$$df$andThenIO$16([7, String(v_$inl11$x[1]), [5, [0]]], [16]),
          [14]
        ),
        [12]
      ),
      [10]
    ),
    [8]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
