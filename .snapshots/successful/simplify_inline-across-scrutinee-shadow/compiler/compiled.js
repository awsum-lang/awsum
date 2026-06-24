"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __splitOnFirst = (sep, str) => {
    const i = str.indexOf(sep);
    if (i < 0) {
      return [11];
    }
    return [12, [15, str.substring(0, i), str.substring(i + sep.length)]];
  };

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

  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 11: {
          return "NO_OUTER";
        }
        case 12: {
          const v_$inl1$____p0 = s[1];
          {
            const __s = __splitOnFirst(":", v_$inl1$____p0[2]);
            switch (__s[0]) {
              case 11: {
                return "NO_INNER";
              }
              case 12: {
                return v_$inl1$____p0[1];
              }
            }
          }
        }
      }
    })(__splitOnFirst(":", "X:Y:Z")),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
