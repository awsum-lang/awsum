"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }
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

function v_showPair(v_pair){
    {
      const __s = v_pair;
      switch (__s[0]) {
        case 0: {
          const v_first = __s[1];
          const v_second = __s[2];
          return (v_showPairBody)(v_first, v_second);
        }
      }
    }
}

function v_showPairBody(v_first, v_second){
    {
      const __s = __concat("(", v_first);
      switch (__s[0]) {
        case 0: {
          const v__do_e_12_3 = __s[1];
          return [0, v__do_e_12_3];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = __concat(v_s0, ", ");
            switch (__s[0]) {
              case 0: {
                const v__do_e_13_3 = __s[1];
                return [0, v__do_e_13_3];
              }
              case 1: {
                const v_s1 = __s[1];
                {
                  const __s = __concat(v_s1, v_second);
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_14_3 = __s[1];
                      return [0, v__do_e_14_3];
                    }
                    case 1: {
                      const v_s2 = __s[1];
                      return __concat(v_s2, ")");
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
}

function main(v__input){
    return (v__let_2)((v_showPair)([0, "hello", "world"]));
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();