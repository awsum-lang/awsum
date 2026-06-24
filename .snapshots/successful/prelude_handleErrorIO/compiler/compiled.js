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

  const v_reFailC = [6, [2286545437, [26]]];

  const v_inErrB = [6, [2269767818, [25]]];

  const v_inErrA = [6, [2252990199, [24]]];

  const v_$apply$$df$mapIO$36 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 45: {
          return v_$x;
        }
        case 46: {
          const v_$pk__46 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__46;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$mapIO$36 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_a = v_io[1];
          return v_$apply$$df$mapIO$36(v_$k, [5, String(v_a)]);
        }
        case 6: {
          return v_$apply$$df$mapIO$36(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [46, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$8 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 31: {
          return v_$x;
        }
        case 32: {
          const v_$pk__32 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__32;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$8(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$8(v_$k, [5, 55 | 0]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [32, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$44 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 49: {
          return v_$x;
        }
        case 50: {
          const v_$pk__50 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__50;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$44 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$44(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$44(
            v_$k,
            (s => {
              switch (s[0]) {
                case 2269767818: {
                  return [7, "ErrB", [5, [0]]];
                }
                case 2286545437: {
                  return [7, "ErrC", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [50, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$40 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 47: {
          return v_$x;
        }
        case 48: {
          const v_$pk__48 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__48;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$40 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$40(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$40(v_$k, [7, "ErrB", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [48, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$4 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$4(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$4(
            v_$k,
            (s => {
              switch (s[0]) {
                case 2252990199: {
                  return [5, 21 | 0];
                }
                case 2269767818: {
                  return [5, 22 | 0];
                }
              }
            })(v_io[1])
          );
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

  const v_dispatchA = v_$cps$$df$handleErrorIO$4(v_inErrA, [29]);

  const v_dispatchB = v_$cps$$df$handleErrorIO$4(v_inErrB, [29]);

  const v_$apply$$df$handleErrorIO$28 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 41: {
          return v_$x;
        }
        case 42: {
          const v_$pk__42 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__42;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$28 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$28(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$28(v_$k, [7, "[!]", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [42, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_treeNoError = v_$cps$$df$handleErrorIO$28([7, "[Y]", [5, [0]]], [41]);

  const v_$apply$$df$handleErrorIO$20 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 37: {
          return v_$x;
        }
        case 38: {
          const v_$pk__38 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__38;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$20 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$20(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$20(v_$k, [7, "[R]", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [38, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$handleErrorIO$16 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 35: {
          return v_$x;
        }
        case 36: {
          const v_$pk__36 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__36;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$16 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$16(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$16(v_$k, v_reFailC);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [36, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_refailRow = v_$cps$$df$handleErrorIO$16([6, [24]], [35]);

  const v_$apply$$df$handleErrorIO$12 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 33: {
          return v_$x;
        }
        case 34: {
          const v_$pk__34 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__34;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$12 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$12(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$12(v_$k, [6, [25]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [34, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_nested = v_$cps$$df$handleErrorIO$8(
    v_$cps$$df$handleErrorIO$12([6, [24]], [33]),
    [31]
  );

  const v_refailNarrow = v_$cps$$df$handleErrorIO$12([6, [24]], [33]);

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
          return v_$apply$$df$handleErrorIO$0(v_$k, [5, 11 | 0]);
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

  const v_passthrough = v_$cps$$df$handleErrorIO$0([5, 33 | 0], [27]);

  const v_recover = v_$cps$$df$handleErrorIO$0([6, [24]], [27]);

  const v_$apply$$df$andThenIO$92 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 73: {
          return v_$x;
        }
        case 74: {
          const v_$pk__74 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__74;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$88 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 71: {
          return v_$x;
        }
        case 72: {
          const v_$pk__72 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__72;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$84 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 69: {
          return v_$x;
        }
        case 70: {
          const v_$pk__70 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__70;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$80 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 67: {
          return v_$x;
        }
        case 68: {
          const v_$pk__68 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__68;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$76 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 65: {
          return v_$x;
        }
        case 66: {
          const v_$pk__66 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__66;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$72 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 63: {
          return v_$x;
        }
        case 64: {
          const v_$pk__64 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__64;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$68 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 61: {
          return v_$x;
        }
        case 62: {
          const v_$pk__62 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__62;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$64 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 59: {
          return v_$x;
        }
        case 60: {
          const v_$pk__60 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__60;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$60 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 57: {
          return v_$x;
        }
        case 58: {
          const v_$pk__58 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__58;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$60 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$60(v_$k, [7, "=", [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$60(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [58, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$56 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 55: {
          return v_$x;
        }
        case 56: {
          const v_$pk__56 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__56;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$56 = (v_io, v_$df$andThenIO$56$cap0$0, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$56(v_$k, v_$df$andThenIO$56$cap0$0);
        }
        case 6: {
          return v_$apply$$df$andThenIO$56(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [56, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$52 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 53: {
          return v_$x;
        }
        case 54: {
          const v_$pk__54 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__54;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$52 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$52(v_$k, [7, "\n", [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$52(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [54, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$64 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$64(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "treeNoError", [5, [0]]], [57]),
                v_treeNoError,
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$64(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [60, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$32 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 43: {
          return v_$x;
        }
        case 44: {
          const v_$pk__44 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__44;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$32 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$32(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$32(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [44, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$76 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$76(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "refailNarrow", [5, [0]]], [57]),
                v_$cps$$df$handleErrorIO$40(
                  v_$cps$$df$andThenIO$32(
                    v_$cps$$df$mapIO$36(v_refailNarrow, [45]),
                    [43]
                  ),
                  [47]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$76(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [66, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$80 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$80(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "nested", [5, [0]]], [57]),
                v_$cps$$df$andThenIO$32(
                  v_$cps$$df$mapIO$36(v_nested, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$80(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [68, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$84 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$84(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "passthrough", [5, [0]]], [57]),
                v_$cps$$df$andThenIO$32(
                  v_$cps$$df$mapIO$36(v_passthrough, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$84(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [70, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$88 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$88(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "dispatchB", [5, [0]]], [57]),
                v_$cps$$df$andThenIO$32(
                  v_$cps$$df$mapIO$36(v_dispatchB, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$88(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [72, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$92 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$92(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "dispatchA", [5, [0]]], [57]),
                v_$cps$$df$andThenIO$32(
                  v_$cps$$df$mapIO$36(v_dispatchA, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$92(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [74, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$24 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 39: {
          return v_$x;
        }
        case 40: {
          const v_$pk__40 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__40;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$24 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$24(v_$k, [6, [24]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$24(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [40, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_treePreserve = v_$cps$$df$handleErrorIO$20(
    v_$cps$$df$andThenIO$24([7, "[X]", [5, [0]]], [39]),
    [37]
  );

  const v_$cps$$df$andThenIO$68 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$68(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "treePreserve", [5, [0]]], [57]),
                v_treePreserve,
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$68(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [62, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$48 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 51: {
          return v_$x;
        }
        case 52: {
          const v_$pk__52 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__52;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$48 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$0$andThenIO$48(
            v_$k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$48(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [52, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$72 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$72(
            v_$k,
            v_$cps$$df$andThenIO$52(
              v_$cps$$df$andThenIO$56(
                v_$cps$$df$andThenIO$60([7, "refailRow", [5, [0]]], [57]),
                v_$cps$$df$handleErrorIO$44(
                  v_$cps$$df$$rowmono$0$andThenIO$48(
                    v_$cps$$df$mapIO$36(v_refailRow, [45]),
                    [51]
                  ),
                  [49]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$72(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [64, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$andThenIO$64(
    v_$cps$$df$andThenIO$68(
      v_$cps$$df$andThenIO$72(
        v_$cps$$df$andThenIO$76(
          v_$cps$$df$andThenIO$80(
            v_$cps$$df$andThenIO$84(
              v_$cps$$df$andThenIO$88(
                v_$cps$$df$andThenIO$92(
                  v_$cps$$df$andThenIO$52(
                    v_$cps$$df$andThenIO$56(
                      v_$cps$$df$andThenIO$60([7, "recover", [5, [0]]], [57]),
                      v_$cps$$df$andThenIO$32(
                        v_$cps$$df$mapIO$36(v_recover, [45]),
                        [43]
                      ),
                      [55]
                    ),
                    [53]
                  ),
                  [73]
                ),
                [71]
              ),
              [69]
            ),
            [67]
          ),
          [65]
        ),
        [63]
      ),
      [61]
    ),
    [59]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
