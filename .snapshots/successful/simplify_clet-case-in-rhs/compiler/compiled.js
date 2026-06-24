"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

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

  const v_$apply$$df$andThenIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 8: {
          return v_$x;
        }
        case 9: {
          const v_$pk__9 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__9;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl4$n = (s => {
            switch (s[0]) {
              case 1: {
                return __lengthUtf8Bytes("abc");
              }
              case 2: {
                return __lengthUtf8Bytes("zz");
              }
            }
          })(__eqUInt32(__lengthUtf8Bytes("no"), 3 >>> 0));
          return v_$apply$$df$andThenIO$0(
            v_$k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 3: {
                    return "OVERFLOW";
                  }
                  case 4: {
                    const v_$inl6$d = s[1];
                    return String(v_$inl6$d);
                  }
                }
              })(__addUInt32(v_$inl4$n, v_$inl4$n)),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [9, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl9$n = (s => {
    switch (s[0]) {
      case 1: {
        return __lengthUtf8Bytes("abc");
      }
      case 2: {
        return __lengthUtf8Bytes("zz");
      }
    }
  })(__eqUInt32(__lengthUtf8Bytes("one"), 3 >>> 0));
  const main = v_$cps$$df$andThenIO$0(
    [
      7,
      (s => {
        switch (s[0]) {
          case 3: {
            return "OVERFLOW";
          }
          case 4: {
            const v_$inl8$d = s[1];
            return String(v_$inl8$d);
          }
        }
      })(__addUInt32(v_$inl9$n, v_$inl9$n)),
      [5, [0]]
    ],
    [8]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
