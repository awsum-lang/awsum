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
    return __print((v_unwrap)([0, "hello"]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();