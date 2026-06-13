"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __predUInt32 = x => x === 0 ? [3, [17]] : [4, x - 1 >>> 0];

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

  const __lengthUtf16CodeUnits = s => s.length >>> 0;

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

  const v_maxStringLengthUtf16CodeUnits = 134217728 >>> 0;

  const v_block = "你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界";

  const v__scc__df_andThenEither_0__lam_13_build = v__args => {
    while (true) {
      switch (v__args[0]) {
        case 8: {
          const v_x = v__args[1];
          switch (v_x[0]) {
            case 3: {
              return v_x;
            }
            case 4: {
              v__args = (v__args[0] = 9, v__args[1] = v__args[2], v__args[2] = v_x[1], v__args);
              continue;
            }
          }
        }
        case 9: {
          v__args = (v__args[0] = 10, v__args);
          continue;
        }
        case 10: {
          const v_n = v__args[1];
          const v_acc = v__args[2];
          {
            const __s = __predUInt32(v_n);
            switch (__s[0]) {
              case 3: {
                return [4, v_acc];
              }
              case 4: {
                const v_m = __s[1];
                v__args = (v__args[0] = 8, v__args[1] = __concat(
                  v_acc,
                  v_acc
                ), v__args[2] = v_m, v__args);
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v_runTest = (s => {
    switch (s[0]) {
      case 3: {
        return "FAIL: build returned Left at the cap";
      }
      case 4: {
        const v_capStr = s[1];
        {
          const __s = __eqUInt32(
            __lengthUtf16CodeUnits(v_capStr),
            v_maxStringLengthUtf16CodeUnits
          );
          switch (__s[0]) {
            case 1: {
              {
                const __s = __concat(v_capStr, "!");
                switch (__s[0]) {
                  case 3: {
                    return "OK";
                  }
                  case 4: {
                    return "FAIL: cap + 1 returned Right";
                  }
                }
              }
            }
            case 2: {
              return "FAIL: built string length is not at cap";
            }
          }
        }
      }
    }
  })(v__scc__df_andThenEither_0__lam_13_build([10, 20 >>> 0, v_block]));

  const main = [7, v_runTest, [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
