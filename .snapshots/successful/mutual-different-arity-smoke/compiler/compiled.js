"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_zero = (0|0);

function main(v__input){
  return __print(String((v_parseExpr)([1])));
}

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
                return v_zero;
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
                return v_zero;
              }
              case 1: {
                const __t0 = [0, v_tok, v_zero];
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
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();