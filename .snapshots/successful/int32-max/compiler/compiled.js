"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __showInt(x){ return String(x); }

function main(v__input){
  return __print(__showInt(v_maxInt32));
}

const v_maxInt32 = (2147483647|0);

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
