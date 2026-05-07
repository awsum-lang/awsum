"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

function v_pureEither(v_x){
    return [1, v_x];
}

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

const v_opA = [1, (1|0)];

const v_opB = [1, (2|0)];

function main(v__wild0){
    return (v__let_2)(((s) => { switch(s[0]) { case 0: { const v__do_e_18_9 = s[1]; return [0, [2252990199, v__do_e_18_9]]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_9 = s[1]; return [0, [2269767818, v__do_e_19_9]]; } case 1: { const v_b = s[1]; return (v_pureEither)(v_b); } } })(v_opB); } } })(v_opA));
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 2252990199: {
                const v___rw = __s[1];
                return [2, "ERR_A", [0, [0]]];
              }
              case 2269767818: {
                const v___rw = __s[1];
                return [2, "ERR_B", [0, [0]]];
              }
              case 2448244154: {
                const v___rw = __s[1];
                return [2, "PARSE_ERROR", [0, [0]]];
              }
            }
          }
        }
        case 1: {
          const v_n = __s[1];
          return [2, String(v_n), [0, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();