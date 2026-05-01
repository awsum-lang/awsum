"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_bindEither(v_x, v_k){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return [0, v_e];
        }
        case 1: {
          const v_a = __s[1];
          return (v_k)(v_a);
        }
      }
    }
}

function v_pureEither(v_x){
    return [1, v_x];
}

function v_const(v_x, v__y){
    return v_x;
}

const v_op1 = [1, (1|0)];

const v_op2 = [0, [435006518, [0]]];

const v_op3 = [1, (3|0)];

const v_f = (v_bindEither)(v_op1, v__pap_1);

function v_describe(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 401451280: {
                const v__a = __s[1];
                return "ErrorA";
              }
              case 435006518: {
                const v__c = __s[1];
                return "ErrorC";
              }
              case 451784137: {
                const v__b = __s[1];
                return "ErrorB";
              }
            }
          }
        }
        case 1: {
          const v_n = __s[1];
          return ("Ok " + String(v_n));
        }
      }
    }
}

function main(v__input){
    return __print((v_describe)(v_f));
}

function v__pap_0(v__eta0){
    return (v_const)((v_bindEither)(v_op3, v_pureEither), v__eta0);
}

function v__pap_1(v__eta0){
    return (v_const)((v_bindEither)(v_op2, v__pap_0), v__eta0);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();