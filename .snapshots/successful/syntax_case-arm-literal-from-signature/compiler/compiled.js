"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_firstZero(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          return (0|0);
        }
        case 1: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 0: {
                return (0|0);
              }
              case 1: {
                const v_n = __s[1];
                return v_n;
              }
            }
          }
        }
      }
    }
}

function main(v__input){
    return __print(String((v_firstZero)([0])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();