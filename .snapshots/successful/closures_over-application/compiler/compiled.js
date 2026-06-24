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

  const v_$scc$$apply1__applyOnce = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 11: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 9: {
              return v_$arg0;
            }
          }
        }
        case 12: {
          v_$args = (v_$args[0] = 11, v_$args);
          continue;
        }
      }
    }
  };

  const main = [
    7,
    String(v_$scc$$apply1__applyOnce([12, [9], 5 | 0])),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
