"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

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

  const v_mixed = [
    14,
    [2711245919, 1 | 0],
    [
      14,
      [1615808600, "x"],
      [
        14,
        [2711245919, 2 | 0],
        [14, [1615808600, "y"], [14, [2711245919, 3 | 0], [13]]]
      ]
    ]
  ];

  const v__apply_sumRow = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 15: {
          return v__x;
        }
        case 16: {
          const v__pk_16 = v__k[1];
          {
            const __s = __addInt32(v__k[2], v__x);
            switch (__s[0]) {
              case 3: {
                v__k = v__pk_16;
                v__x = 0 | 0;
                continue;
              }
              case 4: {
                const v_r = __s[1];
                v__k = v__pk_16;
                v__x = v_r;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const v__cps_sumRow = (v_xs, v__k) => {
    while (true) {
      switch (v_xs[0]) {
        case 13: {
          return v__apply_sumRow(v__k, 0 | 0);
        }
        case 14: {
          const v_h = v_xs[1];
          const v_t = v_xs[2];
          switch (v_h[0]) {
            case 1615808600: {
              v_xs = v_t;
              continue;
            }
            case 2711245919: {
              v__k = [16, v__k, v_h[1]];
              v_xs = v_t;
              continue;
            }
          }
        }
      }
    }
  };

  const main = [7, String(v__cps_sumRow(v_mixed, [15])), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
