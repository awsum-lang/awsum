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
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v__inl6_x = [4, 7 | 0];
  const v__inl13_r = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl6_x;
      }
      case 4: {
        return [3, [365691641, [26]]];
      }
    }
  })(v__inl6_x);
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v__inl13_r[1];
            switch (__s[0]) {
              case 365691641: {
                return "C";
              }
            }
          }
        }
        case 4: {
          return String(v__inl13_r[1]);
        }
      }
    })(v__inl13_r),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
