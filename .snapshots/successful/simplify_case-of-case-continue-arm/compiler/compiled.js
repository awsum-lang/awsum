"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqUInt32 = (a, b) => a === b ? [1] : [2];

  const __subUInt32 = (a, b) => {
    const d = a - b;
    return d < 0 ? [3, [17]] : [4, d >>> 0];
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

  const v_go = v_n => {
    while (true) {
      let v__inl2_scrut;
      $join1: {
        const __s = __eqUInt32(v_n, 0 >>> 0);
        switch (__s[0]) {
          case 1: {
            return String(v_n);
          }
          case 2: {
            v__inl2_scrut = __eqUInt32(v_n, 1 >>> 0);
            break $join1;
          }
        }
      }
      switch (v__inl2_scrut[0]) {
        case 1: {
          return String(v_n);
        }
        case 2: {
          {
            const __s = __subUInt32(v_n, 1 >>> 0);
            switch (__s[0]) {
              case 3: {
                return "E";
              }
              case 4: {
                const v_m = __s[1];
                v_n = v_m;
                continue;
              }
            }
          }
        }
      }
    }
  };

  const main = [7, v_go(100000 >>> 0), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
