"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function main(v__input){
  return __print(((((((((((String(v_minInt32) + ", ") + String(v_negative)) + ", ") + String(v_zero)) + ", ") + String(v_positive)) + ", ") + String(v_manyDigits)) + ", ") + String(v_maxInt32)));
}

const v_minInt32 = (-2147483648|0);

const v_negative = (-42|0);

const v_zero = (0|0);

const v_positive = (7|0);

const v_manyDigits = (1234567|0);

const v_maxInt32 = (2147483647|0);

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
