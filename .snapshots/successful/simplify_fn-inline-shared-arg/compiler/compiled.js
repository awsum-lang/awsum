"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addUInt32 = (a, b) => {
    const s = a + b;
    return s > 4294967295 ? [3, [18]] : [4, s >>> 0];
  };

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

  const v_$inl3$n = __lengthUtf8Bytes(String(-123456 | 0));
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          return "OVERFLOW";
        }
        case 4: {
          const v_$inl2$d = s[1];
          return String(v_$inl2$d);
        }
      }
    })(__addUInt32(v_$inl3$n, v_$inl3$n)),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
