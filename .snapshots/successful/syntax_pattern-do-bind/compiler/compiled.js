"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [882564211, [0]]]; if (s < -2147483648) return [0, [3768445577, [0]]]; return [1, s|0]; }

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

function v_opTuple(v__wild0){
    return [1, [0, (1|0), (2|0), (3|0)]];
}

function main(v_rawArg){
    return (v__let_2)(((s) => { switch(s[0]) { case 0: { const v__do_e_10_9 = s[1]; return [0, v__do_e_10_9]; } case 1: { const v_raw = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_11_9 = s[1]; return [0, [2448244154, v__do_e_11_9]]; } case 1: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v_a = s[1]; const v_b = s[2]; const v_c = s[3]; return (v_pureEither)(((s) => { switch(s[0]) { case 0: { const v___w0 = s[1]; return v_c; } case 1: { const v_ab = s[1]; return ((s) => { switch(s[0]) { case 0: { const v___w0 = s[1]; return v_c; } case 1: { const v_abc = s[1]; return v_abc; } } })(__addInt32(v_ab, v_c)); } } })(__addInt32(v_a, v_b))); } } })(v___p0); } } })((v_opTuple)(v_raw)); } } })(v_rawArg));
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
              case 502975519: {
                const v___rw = __s[1];
                return [2, "UNPAIRED_UTF16_SURROGATE", [0, [0]]];
              }
              case 589989748: {
                const v___rw = __s[1];
                return [2, "STRING_TOO_LONG", [0, [0]]];
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
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();