"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function main(v__input){
    return __print("ok");
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();