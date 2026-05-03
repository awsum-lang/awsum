"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v_value = __s[1];
          return v_value;
        }
      }
    }
}

function main(v__input){
    return __print((v_unwrap)((v__df_wrap_0)("wrapped")));
}

function v__con_Box(v__x0){
    return [0, v__x0];
}

function v__df_wrap_0(v_x){
    return (v__con_Box)(v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();