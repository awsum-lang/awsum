"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_opA(v_n){
    return [1, v_n];
}

function v_opB(v__n){
    return [0, [0]];
}

function v_liftA(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return [0, [2252990199, v_e]];
        }
        case 1: {
          const v_n = __s[1];
          return [1, v_n];
        }
      }
    }
}

function v_liftB(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return [0, [2269767818, v_e]];
        }
        case 1: {
          const v_n = __s[1];
          return [1, v_n];
        }
      }
    }
}

function v_run(v_x){
    {
      const __s = (v_liftA)((v_opA)(v_x));
      switch (__s[0]) {
        case 0: {
          const v__do_e_28_3 = __s[1];
          return [0, v__do_e_28_3];
        }
        case 1: {
          const v_a = __s[1];
          return (v_liftB)((v_opB)(v_a));
        }
      }
    }
}

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
                return "ErrA";
              }
              case 2269767818: {
                const v___rw = __s[1];
                return "ErrB";
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
    return __print((v_describe)((v_run)((5|0))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();