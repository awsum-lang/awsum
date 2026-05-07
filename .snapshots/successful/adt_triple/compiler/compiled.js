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

function v_showTriple(v_t){
    {
      const __s = v_t;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          const v_c = __s[3];
          return (v_h0)(v_a, v_b, v_c);
        }
      }
    }
}

function main(v__input){
    return (v__let_2)((v_showTriple)([0, "one", "two", "three"]));
}

function v_h0(v_a, v_b, v_c){
    {
      const __s = __concat(v_a, " ");
      switch (__s[0]) {
        case 0: {
          const v__do_e_19_3 = __s[1];
          return [0, v__do_e_19_3];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = __concat(v_s0, v_b);
            switch (__s[0]) {
              case 0: {
                const v__do_e_20_3 = __s[1];
                return [0, v__do_e_20_3];
              }
              case 1: {
                const v_s1 = __s[1];
                {
                  const __s = __concat(v_s1, " ");
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_21_3 = __s[1];
                      return [0, v__do_e_21_3];
                    }
                    case 1: {
                      const v_s2 = __s[1];
                      return __concat(v_s2, v_c);
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