"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_succOk = String(42 | 0);

  const v_subUnderflow = "U";

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

  const v_negOverflow = "O";

  const v_addOverflow = "O";

  const v_addOk = String(12 | 0);

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
          return v_$apply$$df$andThenIO$8(v_$k, [7, v_negOverflow, [5, [0]]]);
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
          return v_$apply$$df$andThenIO$4(v_$k, [7, ";", [5, [0]]]);
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

  const v_$apply$$df$andThenIO$28 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$28 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$28(v_$k, [7, ";", [5, [0]]]);
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

  const v_$apply$$df$andThenIO$24 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$24 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$24(v_$k, [7, v_addOverflow, [5, [0]]]);
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

  const v_$apply$$df$andThenIO$20 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 18: {
          return v_$x;
        }
        case 19: {
          const v_$pk__19 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__19;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$20 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$20(v_$k, [7, ";", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [19, v_$k, v_s];
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
          return v_$apply$$df$andThenIO$16(v_$k, [7, v_subUnderflow, [5, [0]]]);
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
          return v_$apply$$df$andThenIO$12(v_$k, [7, ";", [5, [0]]]);
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
          return v_$apply$$df$andThenIO$0(v_$k, [7, v_succOk, [5, [0]]]);
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

  const main = v_$cps$$df$andThenIO$0(
    v_$cps$$df$andThenIO$4(
      v_$cps$$df$andThenIO$8(
        v_$cps$$df$andThenIO$12(
          v_$cps$$df$andThenIO$16(
            v_$cps$$df$andThenIO$20(
              v_$cps$$df$andThenIO$24(
                v_$cps$$df$andThenIO$28([7, v_addOk, [5, [0]]], [22]),
                [20]
              ),
              [18]
            ),
            [16]
          ),
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
