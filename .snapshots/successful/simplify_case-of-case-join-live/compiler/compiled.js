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

  const v_$inl5$s = "abc";
  const main = [
    7,
    (() => {
      let v_$inl4$scrut;
      $join3: {
        const __s = __eqUInt32(__lengthUtf8Bytes(v_$inl5$s), 0 >>> 0);
        switch (__s[0]) {
          case 1: {
            return "other";
          }
          case 2: {
            v_$inl4$scrut = __eqUInt32(__lengthUtf8Bytes(v_$inl5$s), 3 >>> 0);
            break $join3;
          }
        }
      }
      switch (v_$inl4$scrut[0]) {
        case 1: {
          return v_$inl5$s;
        }
        case 2: {
          return "other";
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
