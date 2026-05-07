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

const v_n = (42|0);

const v_basic = String(v_n);

const v_chained = (v_wrap)((v_wrap)(String(v_n)));

const v_viaLambda = (v__lam_2)(v_n);

function v_wrap(v_s){
    return v_s;
}

const v_joined = ((s) => { switch(s[0]) { case 0: { const v__do_e_25_3 = s[1]; return [0, v__do_e_25_3]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_26_3 = s[1]; return [0, v__do_e_26_3]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_27_3 = s[1]; return [0, v__do_e_27_3]; } case 1: { const v_c = s[1]; return __concat(v_c, v_viaLambda); } } })(__concat(v_b, "|")); } } })(__concat(v_a, v_chained)); } } })(__concat(v_basic, "|"));

function main(v__input){
    {
      const __s = v_joined;
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

function v__lam_2(v_i){
    return String(v_i);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();