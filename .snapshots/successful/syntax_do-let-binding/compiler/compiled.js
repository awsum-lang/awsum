"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [882564211, [0]]]; if (s < -2147483648) return [0, [3768445577, [0]]]; return [1, s|0]; }
function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [0, [882564211, [0]]]; if (p < -2147483648) return [0, [3768445577, [0]]]; return [1, p|0]; }
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

function v_step1(v_n){
    {
      const __s = __addInt32(v_n, (10|0));
      switch (__s[0]) {
        case 0: {
          const v__e = __s[1];
          return [0, "overflow"];
        }
        case 1: {
          const v_m = __s[1];
          return [1, v_m];
        }
      }
    }
}

function v_step2(v_n){
    {
      const __s = __mulInt32(v_n, (2|0));
      switch (__s[0]) {
        case 0: {
          const v__e = __s[1];
          return [0, "overflow"];
        }
        case 1: {
          const v_m = __s[1];
          return [1, v_m];
        }
      }
    }
}

function v_run(v_start){
    {
      const __s = (v_step1)(v_start);
      switch (__s[0]) {
        case 0: {
          const v__do_e_18_3 = __s[1];
          return [0, [1615808600, v__do_e_18_3]];
        }
        case 1: {
          const v_a = __s[1];
          return (v__let_2)(v_a, "answer=");
        }
      }
    }
}

function v_renderErr(v_e){
    {
      const __s = v_e;
      switch (__s[0]) {
        case 589989748: {
          const v___rw = __s[1];
          return [1, "STRING_TOO_LONG"];
        }
        case 1615808600: {
          const v_s = __s[1];
          return __concat("err: ", v_s);
        }
      }
    }
}

function main(v__input){
    {
      const __s = (v_run)((5|0));
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = (v_renderErr)(v_e);
            switch (__s[0]) {
              case 0: {
                const v___w0 = __s[1];
                return [2, "STRING_TOO_LONG", [0, [0]]];
              }
              case 1: {
                const v_out = __s[1];
                return [2, v_out, [0, [0]]];
              }
            }
          }
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

function v__let_2(v_a, v_prefix){
    {
      const __s = (v_step2)(v_a);
      switch (__s[0]) {
        case 0: {
          const v__do_e_20_3 = __s[1];
          return [0, [1615808600, v__do_e_20_3]];
        }
        case 1: {
          const v_b = __s[1];
          return __concat(v_prefix, String(v_b));
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();