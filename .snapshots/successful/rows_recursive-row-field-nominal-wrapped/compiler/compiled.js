"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

  const v_v = [25, [1938575252, [12, [25, [1938575252, [12, [24]]]]]]];

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

  const v_$apply$walk = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 26: {
          return v_$x;
        }
        case 27: {
          const v_$pk__27 = v_$k[1];
          {
            const __s = __succInt32(v_$x);
            switch (__s[0]) {
              case 3: {
                v_$k = v_$pk__27;
                v_$x = 0 | 0;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                v_$k = v_$pk__27;
                v_$x = v_r;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v_$cps$walk = (v_c, v_$k) => {
    while (true) {
      switch (v_c[0]) {
        case 24: {
          return v_$apply$walk(v_$k, 0 | 0);
        }
        case 25: {
          const v_x = v_c[1];
          {
            const __s = v_x[1];
            switch (__s[0]) {
              case 11: {
                return v_$apply$walk(v_$k, 0 | 0);
              }
              case 12: {
                const v_rest = __s[1];
                v_$k = [27, v_$k];
                v_c = v_rest;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const main = [7, String(v_$cps$walk(v_v, [26])), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
