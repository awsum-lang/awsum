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

  const v_$scc$parseBinary__parseExpr = v_$args => {
    while (true) {
      switch (v_$args[0]) {
        case 26: {
          {
            const __s = v_$args[1];
            switch (__s[0]) {
              case 24: {
                return 0 | 0;
              }
              case 25: {
                v_$args = [27, [24]];
                continue;
              }
            }
          }
        }
        case 27: {
          const v_tok = v_$args[1];
          switch (v_tok[0]) {
            case 24: {
              return 0 | 0;
            }
            case 25: {
              v_$args = [26, v_tok, 0 | 0];
              continue;
            }
          }
        }
      }
    }
  };

  const main = [7, String(v_$scc$parseBinary__parseExpr([27, [25]])), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
