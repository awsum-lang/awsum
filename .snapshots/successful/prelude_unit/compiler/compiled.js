"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showUnit(v__wild0){
    return "Unit";
}

function main(v__input){
    return __print((v_showUnit)([0]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();