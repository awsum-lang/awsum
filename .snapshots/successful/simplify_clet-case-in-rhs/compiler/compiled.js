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
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 8: {
          return v__x;
        }
        case 9: {
          const v__pk_9 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_9;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl4_n = (s => {
            switch (s[0]) {
              case 1: {
                return __lengthUtf8Bytes("abc");
              }
              case 2: {
                return __lengthUtf8Bytes("zz");
              }
            }
          })(__eqUInt32(__lengthUtf8Bytes("no"), 3 >>> 0));
          return v__apply__df_andThenIO_0(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 3: {
                    return "OVERFLOW";
                  }
                  case 4: {
                    const v__inl6_d = s[1];
                    return String(v__inl6_d);
                  }
                }
              })(__addUInt32(v__inl4_n, v__inl4_n)),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [9, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl9_n = (s => {
    switch (s[0]) {
      case 1: {
        return __lengthUtf8Bytes("abc");
      }
      case 2: {
        return __lengthUtf8Bytes("zz");
      }
    }
  })(__eqUInt32(__lengthUtf8Bytes("one"), 3 >>> 0));
  const main = v__cps__df_andThenIO_0(
    [
      7,
      (s => {
        switch (s[0]) {
          case 3: {
            return "OVERFLOW";
          }
          case 4: {
            const v__inl8_d = s[1];
            return String(v__inl8_d);
          }
        }
      })(__addUInt32(v__inl9_n, v__inl9_n)),
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
