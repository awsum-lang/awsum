"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
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

  const v_r = [3, [332136403, [24]]];

  const v_$inl13$x = v_r;
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v_$inl13$x[1];
            switch (__s[0]) {
              case 332136403: {
                return "A";
              }
            }
          }
        }
        case 4: {
          return String(v_$inl13$x[1]);
        }
      }
    })(v_$inl13$x),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
