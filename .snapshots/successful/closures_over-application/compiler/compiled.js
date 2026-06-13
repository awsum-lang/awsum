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
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v__scc__apply1_applyOnce = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 11: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 9: {
              return v__arg0;
            }
          }
        }
        case 12: {
          v__args = (v__args[0] = 11, v__args);
          continue;
        }
      }
    }
  };

  const main = [
    7,
    String(v__scc__apply1_applyOnce([12, [9], 5 | 0])),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
