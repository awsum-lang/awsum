"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showPair(v_pair){
    {
      const __s = v_pair;
      switch (__s[0]) {
        case 0: {
          const v_first = __s[1];
          const v_second = __s[2];
          return (((("(" + v_first) + ", ") + v_second) + ")");
        }
      }
    }
}

function main(v__input){
    return __print((v_showPair)([0, "hello", "world"]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();