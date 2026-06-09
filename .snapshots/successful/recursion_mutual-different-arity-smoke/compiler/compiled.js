"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_runIO = v_io => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            {
              const __s = __print(v_s);
              switch (__s[0]) {
                case 0: {
                  const __t0 = v_next;
                  v_io = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__scc_parseBinary_parseExpr = v__args => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 26: {
            const v_tok = __s[1];
            const v__acc = __s[2];
            {
              const __s = v_tok;
              switch (__s[0]) {
                case 24: {
                  return 0 | 0;
                }
                case 25: {
                  const __t0 = [27, [24]];
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 27: {
            const v_tok = __s[1];
            {
              const __s = v_tok;
              switch (__s[0]) {
                case 24: {
                  return 0 | 0;
                }
                case 25: {
                  const __t0 = [26, v_tok, 0 | 0];
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_parseExpr = v_tok => v__scc_parseBinary_parseExpr([27, v_tok]);

  const main = [7, String(v_parseExpr([25])), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
