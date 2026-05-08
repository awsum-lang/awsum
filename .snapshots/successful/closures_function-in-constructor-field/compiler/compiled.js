"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [882564211, [0]]]; if (s < -2147483648) return [0, [3768445577, [0]]]; return [1, s|0]; }
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

function v_double(v_n){
    return __addInt32(v_n, v_n);
}

function v_triple(v_n){
    {
      const __s = __addInt32(v_n, v_n);
      switch (__s[0]) {
        case 0: {
          const v__do_e_16_3 = __s[1];
          return [0, v__do_e_16_3];
        }
        case 1: {
          const v_m = __s[1];
          return __addInt32(v_m, v_n);
        }
      }
    }
}

function v_callBox(v_b, v_x){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v_f = __s[1];
          return (v__apply1)(v_f, v_x);
        }
      }
    }
}

const v_formatOutputs = ((s) => { switch(s[0]) { case 0: { const v__do_e_25_3 = s[1]; return [0, v__do_e_25_3]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_26_3 = s[1]; return [0, v__do_e_26_3]; } case 1: { const v_t = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_27_3 = s[1]; return [0, [3768445577, v__do_e_27_3]]; } case 1: { const v_ds = s[1]; return __concat(v_ds, String(v_t)); } } })(__concat(String(v_d), " ")); } } })((v_callBox)([0, [1]], (7|0))); } } })((v_callBox)([0, [0]], (7|0)));

function main(v__input){
    {
      const __s = v_formatOutputs;
      switch (__s[0]) {
        case 0: {
          const v__e = __s[1];
          return [2, "error", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

function v__apply1(v__cl, v__arg0){
    {
      const __s = v__cl;
      switch (__s[0]) {
        case 0: {
          return (v_double)(v__arg0);
        }
        case 1: {
          return (v_triple)(v__arg0);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();