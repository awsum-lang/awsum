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
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v__inl1_n = __lengthUtf8Bytes(String(-2000000000 | 0));
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 1: {
          return "zero";
        }
        case 2: {
          {
            const __s = __eqUInt32(v__inl1_n, 1 >>> 0);
            switch (__s[0]) {
              case 1: {
                return "one";
              }
              case 2: {
                {
                  const __s = __eqUInt32(v__inl1_n, 2 >>> 0);
                  switch (__s[0]) {
                    case 1: {
                      return "two";
                    }
                    case 2: {
                      {
                        const __s = __eqUInt32(v__inl1_n, 11 >>> 0);
                        switch (__s[0]) {
                          case 1: {
                            return "eleven";
                          }
                          case 2: {
                            return String(v__inl1_n);
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    })(__eqUInt32(v__inl1_n, 0 >>> 0)),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
