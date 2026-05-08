"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
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
}

const main = [2, String((v_parseExpr)([1])), [0, [0]]];

function v__scc_parseBinary_parseExpr(v__args){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v_tok = __s[1];
          const v__acc = __s[2];
          {
            const __s = v_tok;
            switch (__s[0]) {
              case 0: {
                return (0|0);
              }
              case 1: {
                const __t0 = [1, [0]];
                v__args = __t0;
                continue;
              }
            }
          }
        }
        case 1: {
          const v_tok = __s[1];
          {
            const __s = v_tok;
            switch (__s[0]) {
              case 0: {
                return (0|0);
              }
              case 1: {
                const __t0 = [0, v_tok, (0|0)];
                v__args = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_parseExpr(v_tok){
    return (v__scc_parseBinary_parseExpr)([1, v_tok]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();