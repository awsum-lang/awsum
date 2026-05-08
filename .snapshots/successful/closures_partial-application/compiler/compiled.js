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

function v_wrap(v_s){
    return [0, v_s];
}

function v_unwrap(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v_value = __s[1];
          return v_value;
        }
      }
    }
}

function v_compose(v_f, v_g, v_x){
    return (v__apply1)(v_f, (v__apply1)(v_g, v_x));
}

function main(v__input){
    return [2, (v__df_apply_0)("chain", [0], [1]), [0, [0]]];
}

function v__df_apply_0(v_x, v__df_apply_0_cap0_0, v__df_apply_0_cap0_1){
    return (v_compose)(v__df_apply_0_cap0_0, v__df_apply_0_cap0_1, v_x);
}

function v__apply1(v__cl, v__arg0){
    {
      const __s = v__cl;
      switch (__s[0]) {
        case 0: {
          return (v_unwrap)(v__arg0);
        }
        case 1: {
          return (v_wrap)(v__arg0);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();