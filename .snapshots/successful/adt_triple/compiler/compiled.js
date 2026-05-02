"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showTriple(v_t){
    {
      const __s = v_t;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          const v_c = __s[3];
          return ((((v_a + " ") + v_b) + " ") + v_c);
        }
      }
    }
}

function main(v__input){
    return __print((v_showTriple)([0, "one", "two", "three"]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();