"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_say(v__eta0){
    return __print(v__eta0);
}

function main(v_inputArg){
    {
      const __s = v_inputArg;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("INPUT_ERROR");
        }
        case 1: {
          const v_input = __s[1];
          return (v_say)(v_input);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();