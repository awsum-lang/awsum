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

  const v_action = [6, [24]];

  const v_$apply$$df$mapIOError$0 = (v_$k, v_$x) => {
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

  const v_$cps$$df$mapIOError$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$mapIOError$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$mapIOError$0(v_$k, [6, [25]]);
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

  const v_$apply$$df$handleErrorIO$4 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$4(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$4(v_$k, [7, "ErrB", [5, [0]]]);
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

  const main = v_$cps$$df$handleErrorIO$4(
    v_$cps$$df$mapIOError$0(v_action, [26]),
    [28]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
