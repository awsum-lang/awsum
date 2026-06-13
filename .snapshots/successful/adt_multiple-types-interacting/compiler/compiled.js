"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const main = (() => {
    let v__inl8_scrut;
    $join7: {
      const __s = __concat(
        (v__inl2_bc =>
          (s => {
            switch (s[0]) {
              case 24: {
                return "red";
              }
              case 25: {
                return "green";
              }
            }
          })(v__inl2_bc[1]))([27, [24]]),
        " "
      );
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s0 = __s[1];
          v__inl8_scrut = __concat(
            v_s0,
            (v__inl4_r =>
              (v__inl3_bc =>
                (s => {
                  switch (s[0]) {
                    case 24: {
                      return "red";
                    }
                    case 25: {
                      return "green";
                    }
                  }
                })(v__inl3_bc[1]))(v__inl4_r[1]))([28, [27, [25]]])
          );
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
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
