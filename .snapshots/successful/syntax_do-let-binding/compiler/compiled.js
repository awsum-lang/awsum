"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [0, [882564211, [0]]]; if (s < -2147483648) return [0, [3768445577, [0]]]; return [1, s|0]; }
function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [0, [882564211, [0]]]; if (p < -2147483648) return [0, [3768445577, [0]]]; return [1, p|0]; }

function v_pureEither(v_x){
    return [1, v_x];
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
          return [0, v__do_e_18_3];
        }
        case 1: {
          const v_a = __s[1];
          return (v__let_1)(v_a, "answer=");
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
          return __print(("err: " + v_e));
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

function v__let_1(v_a, v_prefix){
    {
      const __s = (v_step2)(v_a);
      switch (__s[0]) {
        case 0: {
          const v__do_e_20_3 = __s[1];
          return [0, v__do_e_20_3];
        }
        case 1: {
          const v_b = __s[1];
          return (v_pureEither)((v_prefix + String(v_b)));
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();