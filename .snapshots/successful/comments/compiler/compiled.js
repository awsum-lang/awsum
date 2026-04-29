"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function main(v_input){
    return __print(v_input);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();