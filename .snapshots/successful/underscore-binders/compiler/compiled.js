"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_greeting(v__wild0){
    return "hi";
}

function v_unwrapBox(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return "unwrapped";
        }
      }
    }
}

function v_unwrapBoxNamed(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          const v__v = __s[1];
          return "unwrapped-named";
        }
      }
    }
}

function v_showPair(v_p){
    {
      const __s = v_p;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          const v___w1 = __s[2];
          return "paired";
        }
      }
    }
}

function main(v__input){
    return __print((((((((v_greeting)("x") + " ") + (v_unwrapBox)([0, "a"])) + " ") + (v_unwrapBoxNamed)([0, "b"])) + " ") + (v_showPair)([0, "l", "r"])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();