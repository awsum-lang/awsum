"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v__inl2___input = [12, [1]];
  const v_widened = [
    1454647603,
    (s => {
      switch (s[0]) {
        case 11: {
          return v__inl2___input;
        }
        case 12: {
          return [12, [796142685, v__inl2___input[1]]];
        }
      }
    })(v__inl2___input)
  ];

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

  const v__inl4_x = v_widened;
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 11: {
          return "N";
        }
        case 12: {
          const v__inl3_inner = s[1];
          {
            const __s = v__inl3_inner[1];
            switch (__s[0]) {
              case 1: {
                return "T";
              }
              case 2: {
                return "F";
              }
            }
          }
        }
      }
    })(v__inl4_x[1]),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
