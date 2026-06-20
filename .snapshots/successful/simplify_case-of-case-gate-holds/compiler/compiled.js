"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v__inl5_b = __eqUInt32(__lengthUtf8Bytes("x"), 9 >>> 0);
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 1: {
          {
            const __s = __concat("a", "b");
            switch (__s[0]) {
              case 3: {
                return "overflow";
              }
              case 4: {
                const v__inl2_ab = __s[1];
                {
                  const __s = __concat(v__inl2_ab, "c");
                  switch (__s[0]) {
                    case 3: {
                      return "overflow2";
                    }
                    case 4: {
                      const v__inl4_abc = __s[1];
                      return v__inl4_abc;
                    }
                  }
                }
              }
            }
          }
        }
        case 2: {
          return "no";
        }
      }
    })(
      (s => {
        switch (s[0]) {
          case 1: {
            return v__inl5_b;
          }
          case 2: {
            return [1];
          }
        }
      })(v__inl5_b)
    ),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
