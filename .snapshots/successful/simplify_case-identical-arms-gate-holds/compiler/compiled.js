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

  const v_rebuild = (v_k, v_m) => {
    while (true) {
      {
        const __s = __eqUInt32(v_k, 0 >>> 0);
        switch (__s[0]) {
          case 1: {
            return v_m;
          }
          case 2: {
            {
              const __s = __predUInt32(v_k);
              switch (__s[0]) {
                case 3: {
                  return v_m;
                }
                case 4: {
                  const v_j = __s[1];
                  switch (v_m[0]) {
                    case 11: {
                      v_k = v_j;
                      v_m = [12, 5 >>> 0];
                      continue;
                    }
                    case 12: {
                      v_k = v_j;
                      v_m = [12, 5 >>> 0];
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "TOO_LONG", [5, [0]]];
      }
      case 4: {
        const v_out = s[1];
        return [7, v_out, [5, [0]]];
      }
    }
  })(
    __concat(
      (s => {
        switch (s[0]) {
          case 15: {
            const v_$inl1$a = s[1];
            {
              const __s = __concat(v_$inl1$a, v_$inl1$a);
              switch (__s[0]) {
                case 3: {
                  return "TOO_LONG";
                }
                case 4: {
                  const v_$inl4$r = __s[1];
                  return v_$inl4$r;
                }
              }
            }
          }
        }
      })([15, "ab", "cd"]),
      (() => {
        const v_$inl6$m = v_rebuild(
          1 >>> 0,
          (s => {
            switch (s[0]) {
              case 1: {
                return [12, 9 >>> 0];
              }
              case 2: {
                return [11];
              }
            }
          })(__eqUInt32(__lengthUtf8Bytes("x"), 1 >>> 0))
        );
        return (s => {
          switch (s[0]) {
            case 11: {
              return "none";
            }
            case 12: {
              return String(v_$inl6$m[1]);
            }
          }
        })(v_$inl6$m);
      })()
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
