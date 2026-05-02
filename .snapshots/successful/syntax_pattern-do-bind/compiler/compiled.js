"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [882564211, [0]]]; if (s < -2147483648) return [0, [3768445577, [0]]]; return [1, s|0]; }

function v_pureEither(v_x){
    return [1, v_x];
}

function v_opTuple(v__wild0){
    return [1, [0, (1|0), (2|0), (3|0)]];
}

function main(v_raw){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_10_9 = s[1]; return [0, v__do_e_10_9]; } case 1: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v_a = s[1]; const v_b = s[2]; const v_c = s[3]; return (v_pureEither)(((s) => { switch(s[0]) { case 0: { const v___w0 = s[1]; return v_c; } case 1: { const v_ab = s[1]; return ((s) => { switch(s[0]) { case 0: { const v___w0 = s[1]; return v_c; } case 1: { const v_abc = s[1]; return v_abc; } } })(__addInt32(v_ab, v_c)); } } })(__addInt32(v_a, v_b))); } } })(v___p0); } } })((v_opTuple)(v_raw)));
}

function v__let_1(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("PARSE_ERROR");
        }
        case 1: {
          const v_n = __s[1];
          return __print(String(v_n));
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();