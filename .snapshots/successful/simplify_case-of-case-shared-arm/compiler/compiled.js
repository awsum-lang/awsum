"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

  const __lengthUtf8Bytes = s => new TextEncoder().encode(s).length >>> 0;

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

  const v_$inl5$b = __eqUInt32(__lengthUtf8Bytes("x"), 9 >>> 0);
  const main = [
    7,
    (() => {
      let v_$inl4$scrut;
      $join3: {
        switch (v_$inl5$b[0]) {
          case 1: {
            v_$inl4$scrut = v_$inl5$b;
            break $join3;
          }
          case 2: {
            return "yes";
          }
        }
      }
      switch (v_$inl4$scrut[0]) {
        case 1: {
          return "yes";
        }
        case 2: {
          return "no";
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
