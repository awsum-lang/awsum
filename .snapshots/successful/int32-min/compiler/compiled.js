"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __showInt(x){ return String(x); }

function main(v__input){
  return __print(__showInt(v_minInt32));
}

const v_minInt32 = (-2147483648|0);

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
