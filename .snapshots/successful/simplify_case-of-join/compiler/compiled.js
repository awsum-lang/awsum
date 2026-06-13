"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

  const __lengthUtf8Bytes = s => new TextEncoder().encode(s).length >>> 0;

  const v_seed = __eqUInt32(__lengthUtf8Bytes(String(42 | 0)), 2 >>> 0);

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

  const v_result = (v__inl2_s0 =>
    (s => {
      switch (s[0]) {
        case 1: {
          return "F";
        }
        case 2: {
          return "T";
        }
      }
    })(
      (s => {
        switch (s[0]) {
          case 1: {
            return __eqUInt32(__lengthUtf8Bytes("xyz"), 3 >>> 0);
          }
          case 2: {
            return v__inl2_s0;
          }
        }
      })(v__inl2_s0)
    ))(v_seed);

  const main = [7, v_result, [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
