"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_say(v__eta0){
    return [2, v__eta0, [0, [0]]];
}

function main(v_inputArg){
    {
      const __s = v_inputArg;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "INPUT_ERROR", [0, [0]]];
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
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();