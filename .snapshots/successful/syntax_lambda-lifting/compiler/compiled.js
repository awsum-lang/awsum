"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_pureEither(v_x){
    return [1, v_x];
}

const v_inc42 = (v__df_apply_0)((42|0));

const v_op1 = [1, (1|0)];

function v_op2WithA(v_n){
    return [1, v_n];
}

const v_g = ((s) => { switch(s[0]) { case 0: { const v__do_e_23_3 = s[1]; return [0, [2252990199, v__do_e_23_3]]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_3 = s[1]; return [0, [2269767818, v__do_e_24_3]]; } case 1: { const v_b = s[1]; return (v_pureEither)(v_b); } } })((v_op2WithA)(v_a)); } } })(v_op1);

function v_describe(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 2252990199: {
                const v___rw = __s[1];
                return [1, "ErrA"];
              }
              case 2269767818: {
                const v___rw = __s[1];
                return [1, "ErrB"];
              }
            }
          }
        }
        case 1: {
          const v_n = __s[1];
          return [1, ("Ok " + String(v_n))];
        }
      }
    }
}

function main(v__input){
    return (v__let_2)(((s) => { switch(s[0]) { case 0: { const v__do_e_37_9 = s[1]; return [0, v__do_e_37_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_38_9 = s[1]; return [0, v__do_e_38_9]; } case 1: { const v_s0 = s[1]; return [1, (v_s0 + v_d)]; } } })([1, (String(v_inc42) + " / ")]); } } })((v_describe)(v_g)));
}

function v__lam_1(v_n){
    return v_n;
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("STRING_TOO_LONG");
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

function v__df_apply_0(v_x){
    return (v__lam_1)(v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();