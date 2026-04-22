"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_advanceStep(v_x){
  while (true) {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          const __t0 = [1];
          v_x = __t0;
          continue;
        }
        case 1: {
          const __t0 = [2];
          v_x = __t0;
          continue;
        }
        case 2: {
          return "Done!";
        }
      }
    }
  }
}

function main(v__input){
  return __print((v_advanceStep)([0]));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
