"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return ("left: " + v_e);
        }
        case 1: {
          const v_v = __s[1];
          return ("right: " + v_v);
        }
      }
    }
}

function main(v__input){
    return __print((((v_unwrap)([0, "bad"]) + ", ") + (v_unwrap)([1, "good"])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();