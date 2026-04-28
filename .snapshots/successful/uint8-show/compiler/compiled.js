"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function main(v__input){
    return __print(((((((String(v_minUInt8) + ", ") + String(v_small)) + ", ") + String(v_aboveSignedByte)) + ", ") + String(v_maxUInt8)));
}

const v_minUInt8 = (0 & 0xFF);

const v_small = (42 & 0xFF);

const v_aboveSignedByte = (200 & 0xFF);

const v_maxUInt8 = (255 & 0xFF);

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();