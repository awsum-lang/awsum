"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_describe(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1615808600: {
          const v_s = __s[1];
          return ("String " + v_s);
        }
        case 2711245919: {
          const v_n = __s[1];
          return ("Int32 " + String(v_n));
        }
      }
    }
}

function main(v__input){
    return __print((v_describe)([1615808600, "hello"]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();