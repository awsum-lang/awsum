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

  const main = (v__inl4_x =>
    (() => {
      let v__inl8_scrut;
      $join7: {
        const __s = v__inl4_x[1];
        switch (__s[0]) {
          case 11: {
            return [7, "Nothing", [5, [0]]];
          }
          case 12: {
            const v__inl3___pa0 = __s[1];
            v__inl8_scrut = (s => {
              switch (s[0]) {
                case 1: {
                  return [4, "Just True"];
                }
                case 2: {
                  return [4, "Just False"];
                }
              }
            })(v__inl3___pa0[1]);
            break $join7;
          }
        }
      }
      switch (v__inl8_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl8_scrut[1], [5, [0]]];
        }
      }
    })())(
    [
      1454647603,
      (v__inl2___input =>
        (s => {
          switch (s[0]) {
            case 11: {
              return v__inl2___input;
            }
            case 12: {
              return [12, [796142685, v__inl2___input[1]]];
            }
          }
        })(v__inl2___input))([12, [1]])
    ]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
