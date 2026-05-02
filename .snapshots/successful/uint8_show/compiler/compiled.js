"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

const v_minUInt8 = (0 & 0xFF);

const v_maxUInt8 = (255 & 0xFF);

function main(v__input){
    return __print(((((((String(v_minUInt8) + ", ") + String((42 & 0xFF))) + ", ") + String((200 & 0xFF))) + ", ") + String(v_maxUInt8)));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();