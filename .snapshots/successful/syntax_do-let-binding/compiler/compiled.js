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

  const main = (v__inl25___input =>
    (s => {
      switch (s[0]) {
        case 3: {
          const v_e = s[1];
          let v__inl32_scrut;
          $join31: {
            switch (v_e[0]) {
              case 589989748: {
                return [7, "STRING_TOO_LONG", [5, [0]]];
              }
            }
          }
          switch (v__inl32_scrut[0]) {
            case 3: {
              return [7, "STRING_TOO_LONG", [5, [0]]];
            }
            case 4: {
              return [7, v__inl32_scrut[1], [5, [0]]];
            }
          }
        }
        case 4: {
          const v_s = s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    })(
      (s => {
        switch (s[0]) {
          case 3: {
            return [3, [589989748, v__inl25___input[1]]];
          }
          case 4: {
            return v__inl25___input;
          }
        }
      })(v__inl25___input)
    ))(__concat("answer=", String(30 | 0)));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
