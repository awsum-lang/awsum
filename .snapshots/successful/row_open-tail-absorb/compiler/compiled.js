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

  const v_$inl2$____input = [12, [1]];
  const main = [
    7,
    (() => {
      let v_$inl5$scrut;
      $join4: {
        switch (v_$inl2$____input[0]) {
          case 11: {
            v_$inl5$scrut = v_$inl2$____input;
            break $join4;
          }
          case 12: {
            return "j";
          }
        }
      }
      switch (v_$inl5$scrut[0]) {
        case 11: {
          return "n";
        }
        case 12: {
          return "j";
        }
      }
    })(),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
