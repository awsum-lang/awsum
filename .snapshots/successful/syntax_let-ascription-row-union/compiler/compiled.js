"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_pureEither(v_x){
    return [1, v_x];
}

const v_opA = [1, (1|0)];

const v_opB = [1, (2|0)];

function main(v__wild0){
    return (v__let_0)(((s) => { switch(s[0]) { case 0: { const v__do_e_29_9 = s[1]; return [0, [2252990199, v__do_e_29_9]]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_30_9 = s[1]; return [0, [2269767818, v__do_e_30_9]]; } case 1: { const v_b = s[1]; return (v_pureEither)(v_b); } } })(v_opB); } } })(v_opA));
}

function v__let_0(v_res){
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
                return __print("ERR_A");
              }
              case 2269767818: {
                const v___rw = __s[1];
                return __print("ERR_B");
              }
              case 2448244154: {
                const v___rw = __s[1];
                return __print("PARSE_ERROR");
              }
            }
          }
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