"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_box){
    {
      const __s = v_box;
      switch (__s[0]) {
        case 0: {
          const v_value = __s[1];
          return v_value;
        }
      }
    }
}

function v_showResult(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          return v_a;
        }
        case 1: {
          const v_e = __s[1];
          return v_e;
        }
      }
    }
}

function main(v__input){
    return __print((((v_unwrap)([0, "from box"]) + " ") + (v_showResult)((v_unwrap)([0, [0, "nested"]]))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();