"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_describe(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1615808600: {
          const v_s = __s[1];
          return [1, ("String " + v_s)];
        }
        case 2711245919: {
          const v_n = __s[1];
          return [1, ("Int32 " + String(v_n))];
        }
      }
    }
}

function main(v__input){
    return (v__let_1)((v_describe)([1615808600, "hello"]));
}

function v__let_1(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("STRING_TOO_LONG");
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();