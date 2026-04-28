"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_say(v__eta0){
  return __print(v__eta0);
}

function main(v_input){
  return (v_say)(v_input);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();