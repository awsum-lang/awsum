"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

  const v_v = [
    25,
    [
      2437051370,
      [26, [3240007001, [25, [2437051370, [26, [3240007001, [24]]]]]]]
    ]
  ];

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

  const v_$apply$$scc$walkA__walkB = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 29: {
          return v_$x;
        }
        case 30: {
          const v_$pk__30 = v_$k[1];
          {
            const __s = __succInt32(v_$x);
            switch (__s[0]) {
              case 3: {
                v_$k = v_$pk__30;
                v_$x = 0 | 0;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                v_$k = v_$pk__30;
                v_$x = v_r;
                continue;
              }
            }
          }
        }
        case 31: {
          const v_$pk__31 = v_$k[1];
          {
            const __s = __succInt32(v_$x);
            switch (__s[0]) {
              case 3: {
                v_$k = v_$pk__31;
                v_$x = 0 | 0;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                v_$k = v_$pk__31;
                v_$x = v_r;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v_$cps$$scc$walkA__walkB = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 27: {
          const v_c = v_$args[1];
          switch (v_c[0]) {
            case 24: {
              return v_$apply$$scc$walkA__walkB(v_$k, 0 | 0);
            }
            case 25: {
              const v_x = v_c[1];
              v_$k = (v_$args[0] = 30, v_$args[1] = v_$k, v_$args);
              v_$args = [28, v_x[1]];
              continue;
            }
          }
        }
        case 28: {
          const v_c = v_$args[1];
          switch (v_c[0]) {
            case 26: {
              const v_x = v_c[1];
              v_$k = (v_$args[0] = 31, v_$args[1] = v_$k, v_$args);
              v_$args = [27, v_x[1]];
              continue;
            }
          }
        }
      }
    }
  };

  const main = [7, String(v_$cps$$scc$walkA__walkB([27, v_v], [29])), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
