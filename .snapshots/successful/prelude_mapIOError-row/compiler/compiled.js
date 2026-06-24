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

  const v_okSrc = [5, 5 | 0];

  const v_failY = [6, [3640903312, [26]]];

  const v_failX = [6, [3657680931, [25]]];

  const v_failSrc = [6, [24]];

  const v_$apply$$df$mapIOError$8 = (v_$k, v_$x) => {
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

  const v_$cps$$df$mapIOError$8 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$mapIOError$8(v_$k, v_io);
        }
        case 6: {
          const v_e = v_io[1];
          return v_$apply$$df$mapIOError$8(
            v_$k,
            [
              6,
              (s => {
                switch (s[0]) {
                  case 3640903312: {
                    return [2269767818, [28]];
                  }
                  case 3657680931: {
                    return [2252990199, [27]];
                  }
                }
              })(v_e)
            ]
          );
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

  const v_remappedX = v_$cps$$df$mapIOError$8(v_failX, [33]);

  const v_remappedY = v_$cps$$df$mapIOError$8(v_failY, [33]);

  const v_$apply$$df$mapIOError$4 = (v_$k, v_$x) => {
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

  const v_$cps$$df$mapIOError$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$mapIOError$4(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$mapIOError$4(v_$k, [6, [2269767818, [28]]]);
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

  const v_mappedB = v_$cps$$df$mapIOError$4(v_failSrc, [31]);

  const v_$apply$$df$mapIOError$0 = (v_$k, v_$x) => {
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

  const v_$cps$$df$mapIOError$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$mapIOError$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$mapIOError$0(v_$k, [6, [2252990199, [27]]]);
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

  const v_mappedA = v_$cps$$df$mapIOError$0(v_failSrc, [29]);

  const v_mappedOk = v_$cps$$df$mapIOError$0(v_okSrc, [29]);

  const v_$apply$$df$mapIO$20 = (v_$k, v_$x) => {
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

  const v_$cps$$df$mapIO$20 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_a = v_io[1];
          return v_$apply$$df$mapIO$20(v_$k, [5, String(v_a)]);
        }
        case 6: {
          return v_$apply$$df$mapIO$20(v_$k, v_io);
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

  const v_$apply$$df$handleErrorIO$24 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$24 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$24(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$24(
            v_$k,
            (s => {
              switch (s[0]) {
                case 2252990199: {
                  return [7, "ErrA", [5, [0]]];
                }
                case 2269767818: {
                  return [7, "ErrB", [5, [0]]];
                }
              }
            })(v_io[1])
          );
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

  const v_$apply$$df$handleErrorIO$12 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$12 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$12(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$12(
            v_$k,
            (s => {
              switch (s[0]) {
                case 2252990199: {
                  return [7, "ErrA", [5, [0]]];
                }
                case 2269767818: {
                  return [7, "ErrB", [5, [0]]];
                }
              }
            })(v_io[1])
          );
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

  const v_$apply$$df$andThenIO$56 = (v_$k, v_$x) => {
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

  const v_$apply$$df$andThenIO$52 = (v_$k, v_$x) => {
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

  const v_$apply$$df$andThenIO$48 = (v_$k, v_$x) => {
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

  const v_$apply$$df$andThenIO$44 = (v_$k, v_$x) => {
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

  const v_$apply$$df$andThenIO$40 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$40 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$40(v_$k, [7, "=", [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$40(v_$k, v_io);
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

  const v_$apply$$df$andThenIO$36 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$36 = (v_io, v_$df$andThenIO$36$cap0$0, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$36(v_$k, v_$df$andThenIO$36$cap0$0);
        }
        case 6: {
          return v_$apply$$df$andThenIO$36(v_$k, v_io);
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

  const v_$apply$$df$andThenIO$32 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$32 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$32(v_$k, [7, "\n", [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$32(v_$k, v_io);
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

  const v_$apply$$df$$rowmono$1$andThenIO$28 = (v_$k, v_$x) => {
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

  const v_$cps$$df$$rowmono$1$andThenIO$28 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$1$andThenIO$28(
            v_$k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$1$andThenIO$28(v_$k, v_io);
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

  const v_$cps$$df$andThenIO$44 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$44(
            v_$k,
            v_$cps$$df$andThenIO$32(
              v_$cps$$df$andThenIO$36(
                v_$cps$$df$andThenIO$40([7, "remappedY", [5, [0]]], [49]),
                v_$cps$$df$handleErrorIO$24(
                  v_$cps$$df$$rowmono$1$andThenIO$28(
                    v_$cps$$df$mapIO$20(v_remappedY, [39]),
                    [43]
                  ),
                  [41]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$44(v_$k, v_io);
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

  const v_$cps$$df$andThenIO$48 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$48(
            v_$k,
            v_$cps$$df$andThenIO$32(
              v_$cps$$df$andThenIO$36(
                v_$cps$$df$andThenIO$40([7, "remappedX", [5, [0]]], [49]),
                v_$cps$$df$handleErrorIO$24(
                  v_$cps$$df$$rowmono$1$andThenIO$28(
                    v_$cps$$df$mapIO$20(v_remappedX, [39]),
                    [43]
                  ),
                  [41]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$48(v_$k, v_io);
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

  const v_$apply$$df$$rowmono$0$andThenIO$16 = (v_$k, v_$x) => {
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

  const v_$cps$$df$$rowmono$0$andThenIO$16 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$$rowmono$0$andThenIO$16(
            v_$k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$16(v_$k, v_io);
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

  const v_$cps$$df$andThenIO$52 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$52(
            v_$k,
            v_$cps$$df$andThenIO$32(
              v_$cps$$df$andThenIO$36(
                v_$cps$$df$andThenIO$40([7, "mappedOk", [5, [0]]], [49]),
                v_$cps$$df$handleErrorIO$12(
                  v_$cps$$df$$rowmono$0$andThenIO$16(
                    v_$cps$$df$mapIO$20(v_mappedOk, [39]),
                    [37]
                  ),
                  [35]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$52(v_$k, v_io);
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

  const v_$cps$$df$andThenIO$56 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$56(
            v_$k,
            v_$cps$$df$andThenIO$32(
              v_$cps$$df$andThenIO$36(
                v_$cps$$df$andThenIO$40([7, "mappedB", [5, [0]]], [49]),
                v_$cps$$df$handleErrorIO$12(
                  v_$cps$$df$$rowmono$0$andThenIO$16(
                    v_$cps$$df$mapIO$20(v_mappedB, [39]),
                    [37]
                  ),
                  [35]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v_$apply$$df$andThenIO$56(v_$k, v_io);
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

  const main = v_$cps$$df$andThenIO$44(
    v_$cps$$df$andThenIO$48(
      v_$cps$$df$andThenIO$52(
        v_$cps$$df$andThenIO$56(
          v_$cps$$df$andThenIO$32(
            v_$cps$$df$andThenIO$36(
              v_$cps$$df$andThenIO$40([7, "mappedA", [5, [0]]], [49]),
              v_$cps$$df$handleErrorIO$12(
                v_$cps$$df$$rowmono$0$andThenIO$16(
                  v_$cps$$df$mapIO$20(v_mappedA, [39]),
                  [37]
                ),
                [35]
              ),
              [47]
            ),
            [45]
          ),
          [57]
        ),
        [55]
      ),
      [53]
    ),
    [51]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
