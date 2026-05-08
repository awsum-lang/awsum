"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

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

function main(v__input){
    return [2, String((v_parseExpr)([1])), [0, [0]]];
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
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();