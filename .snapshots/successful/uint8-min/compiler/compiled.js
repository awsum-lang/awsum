"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __showInt(x){ return String(x); }

function main(v__input){
  return __print(__showInt(v_minUInt8));
}

const v_minUInt8 = (0 & 0xFF);

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
