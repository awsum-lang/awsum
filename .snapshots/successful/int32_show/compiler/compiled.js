"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_minInt32 = (-2147483648|0);

const v_maxInt32 = (2147483647|0);

function main(v__input){
    return __print(((((((((((String(v_minInt32) + ", ") + String((-42|0))) + ", ") + String((0|0))) + ", ") + String((7|0))) + ", ") + String((1234567|0))) + ", ") + String(v_maxInt32)));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();